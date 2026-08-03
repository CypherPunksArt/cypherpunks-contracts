// SPDX-License-Identifier: GPL-3.0

/// @title The CypherPunks auction house

// LICENSE
// AuctionHouse.sol is a modified version of the Nouns NounsAuctionHouseV2.sol
// (vendored unmodified in reference/NounsAuctionHouseV2.sol), itself a
// modified version of Zora's AuctionHouse.sol. GPL-3.0 throughout.
//
// CypherPunks deltas from Nouns V2 (design doc §02 delta table):
//   KEEP VERBATIM: settlement chaining; anti-snipe reset;
//     _safeTransferETHWithFallback + _safeTransferETH (30k stipend,
//     returndata-ignoring assembly, WETH fallback); permissionless settle.
//   STRIP: proxy/UUPS + initializer; Ownable + all owner setters (duration,
//     reserve, increment, buffer); client-id/rewards plumbing; settlement
//     price history & its getters; ReentrancyGuard storage shim; the
//     mint-revert try/catch (the minter is immutable here — the only mint
//     failure is pool exhaustion, handled as the explicit terminal state).
//   ADD: §01 constants baked in; proceeds → immutable splitter; pause per
//     §01/§06 (3-of-5 Safe guardian, instant pause, unpause behind a 48h
//     timelock, in-flight bidding and settlement unaffected); auction #1
//     gated on the Token's genesis state machine (I17 step 4).

pragma solidity 0.8.28;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CypherPunksToken} from "./Token.sol";
import {IWETH} from "./interfaces/IWETH.sol";

contract CypherPunksAuctionHouse is Pausable {
    // ------------------------------------------------------- §01 constants

    /// @notice The duration of a single auction, chained off prior settlement
    uint256 public constant DURATION = 24 hours;

    /// @notice Anti-snipe reset window and extension
    uint256 public constant TIME_BUFFER = 10 minutes;

    /// @notice The minimum percentage difference between bids
    uint8 public constant MIN_BID_INCREMENT_PERCENTAGE = 2;

    /// @notice Absolute outbid floor (doc §01/§06, Rev 2): required increase
    ///         = max(2%, MIN_BID_STEP). Applies to outbids only — the opening
    ///         bid needs only ≥ reserve. Closes the dust region where the
    ///         integer 2% floors to zero.
    uint256 public constant MIN_BID_STEP = 0.001 ether;

    /// @notice The minimum price accepted in an auction
    uint256 public constant RESERVE_PRICE = 0;

    /// @notice Unpause sits behind this delay once scheduled (doc §01)
    uint256 public constant UNPAUSE_DELAY = 48 hours;

    /// @notice The address of the WETH contract — mainnet canonical, hardcoded
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // ----------------------------------------------------------- immutables

    /// @notice The CypherPunks ERC721 token contract
    CypherPunksToken public immutable token;

    /// @notice Immutable proceeds recipient (doc §06); no redirection path
    address public immutable splitter;

    /// @notice The 3-of-5 Safe that may pause / schedule unpause (doc §01)
    address public immutable pauseGuardian;

    // -------------------------------------------------------------- storage

    struct Auction {
        uint96 tokenId;
        uint16 pieceId;
        uint128 amount;
        uint40 startTime;
        uint40 endTime;
        address payable bidder;
        bool settled;
    }

    /// @notice The active auction
    Auction public auctionStorage;

    /// @notice When an unpause was scheduled; zero = none scheduled
    uint256 public unpauseScheduledAt;

    // --------------------------------------------------------------- events

    event AuctionCreated(
        uint256 indexed tokenId, uint256 indexed pieceId, uint256 startTime, uint256 endTime
    );
    event AuctionBid(uint256 indexed tokenId, address sender, uint256 value, bool extended);
    event AuctionExtended(uint256 indexed tokenId, uint256 endTime);
    event AuctionSettled(uint256 indexed tokenId, address winner, uint256 amount);
    event AuctionWalkComplete();
    event UnpauseScheduled(uint256 executableAt);
    event UnpauseCancelled();

    // ---------------------------------------------------------- constructor

    constructor(CypherPunksToken _token, address _splitter, address _pauseGuardian) {
        require(address(_token) != address(0), 'token is zero');
        require(_splitter != address(0), 'splitter is zero');
        require(_pauseGuardian != address(0), 'guardian is zero');
        token = _token;
        splitter = _splitter;
        pauseGuardian = _pauseGuardian;
    }

    /**
     * @notice Open auction #1. Step 4 of the genesis state machine (I17):
     * permissionless, callable exactly once, unreachable until the Token's
     * genesis steps 1–3 are complete.
     */
    function startAuctions() external whenNotPaused {
        require(token.genesisComplete(), 'genesis incomplete');
        require(auctionStorage.startTime == 0, 'auctions already started');
        _createAuction();
    }

    /**
     * @notice Settle the current auction, mint a new CypherPunk, and put it
     * up for auction. The next day's piece is drawn inside this transaction
     * (doc §03; I15).
     */
    function settleCurrentAndCreateNewAuction() external whenNotPaused {
        _settleAuction();
        _createAuction();
    }

    /**
     * @notice Settle the current auction.
     * @dev This function can only be called when the contract is paused.
     */
    function settleAuction() external whenPaused {
        _settleAuction();
    }

    /**
     * @notice Create a bid for a CypherPunk, with a given amount.
     * @dev This contract only accepts payment in ETH.
     */
    function createBid(uint256 punkId) external payable {
        Auction memory _auction = auctionStorage;

        require(_auction.tokenId == punkId, 'Punk not up for auction');
        // This single time check also subsumes the Nouns `startTime != 0` and
        // `!settled` guards: a fresh/settled auction struct has endTime == 0, so
        // `block.timestamp < endTime` is false and bidding is closed. Do not
        // relax this comparison without restoring those explicit guards.
        require(block.timestamp < _auction.endTime, 'Auction expired');
        require(msg.value >= RESERVE_PRICE, 'Must send at least reservePrice');
        // Rev 2 amendment (the single lifted expression from the verbatim
        // block): outbids must increase by max(2%, MIN_BID_STEP); the opening
        // bid (no bidder yet) needs only the reserve.
        uint256 requiredIncrease;
        if (_auction.bidder != address(0)) {
            uint256 pct = (uint256(_auction.amount) * MIN_BID_INCREMENT_PERCENTAGE) / 100;
            requiredIncrease = pct > MIN_BID_STEP ? pct : MIN_BID_STEP;
        }
        require(
            msg.value >= _auction.amount + requiredIncrease,
            'Must send more than last bid by minBidIncrementPercentage amount'
        );

        auctionStorage.amount = uint128(msg.value);
        auctionStorage.bidder = payable(msg.sender);

        // Extend the auction if the bid was received within `TIME_BUFFER` of the auction end time
        bool extended = _auction.endTime - block.timestamp < TIME_BUFFER;

        emit AuctionBid(_auction.tokenId, msg.sender, msg.value, extended);

        if (extended) {
            auctionStorage.endTime = _auction.endTime = uint40(block.timestamp + TIME_BUFFER);
            emit AuctionExtended(_auction.tokenId, _auction.endTime);
        }

        address payable lastBidder = _auction.bidder;

        // Refund the last bidder, if applicable
        if (lastBidder != address(0)) {
            _safeTransferETHWithFallback(lastBidder, _auction.amount);
        }
    }

    /**
     * @notice Get the current auction.
     */
    function auction() external view returns (Auction memory) {
        return auctionStorage;
    }

    // ---------------------------------------------------- pause (doc §01/§06)

    /**
     * @notice Pause the auction house. Instant; guardian only. Halts creation
     * of the NEXT auction only — in-flight bidding and settlement are
     * unaffected (settleAuction is callable while paused).
     */
    function pause() external {
        require(msg.sender == pauseGuardian, 'not guardian');
        if (unpauseScheduledAt != 0) {
            unpauseScheduledAt = 0; // cancels any pending unpause schedule
            emit UnpauseCancelled(); // watchers see cancellation onchain
        }
        if (!paused()) _pause();
    }

    /**
     * @notice Schedule an unpause; executable by anyone after UNPAUSE_DELAY.
     */
    function scheduleUnpause() external whenPaused {
        require(msg.sender == pauseGuardian, 'not guardian');
        unpauseScheduledAt = block.timestamp;
        emit UnpauseScheduled(block.timestamp + UNPAUSE_DELAY);
    }

    /**
     * @notice Execute a matured unpause. Permissionless — the timelock is the
     * gate, not the caller. Starts the next auction if the current one is
     * settled (or none is live) and the walk is not complete.
     */
    function unpause() external whenPaused {
        require(unpauseScheduledAt != 0, 'unpause not scheduled');
        require(block.timestamp >= unpauseScheduledAt + UNPAUSE_DELAY, 'timelock not elapsed');
        unpauseScheduledAt = 0;
        _unpause();

        if (
            token.genesisComplete() && auctionStorage.startTime != 0 && auctionStorage.settled
        ) {
            _createAuction();
        }
    }

    // ------------------------------------------------------------ internals

    /**
     * @notice Create an auction.
     * @dev Mints the next token (drawing its design piece in the same
     * transaction, doc §03) and stores the auction details. Pool exhaustion
     * is the explicit terminal state: after the 9,800th settlement no new
     * auction is created and the walk is complete.
     */
    function _createAuction() internal {
        if (token.poolRemaining() == 0) {
            emit AuctionWalkComplete();
            return;
        }

        uint256 tokenId = token.mintNext(address(this));
        uint16 pieceId = uint16(token.punkForToken(tokenId));

        uint40 startTime = uint40(block.timestamp);
        uint40 endTime = startTime + uint40(DURATION);

        auctionStorage = Auction({
            tokenId: uint96(tokenId),
            pieceId: pieceId,
            amount: 0,
            startTime: startTime,
            endTime: endTime,
            bidder: payable(0),
            settled: false
        });

        emit AuctionCreated(tokenId, pieceId, startTime, endTime);
    }

    /**
     * @notice Settle an auction, finalizing the bid and paying out to the splitter.
     * @dev If there are no bids, the CypherPunk is burned (Nouns-verbatim).
     */
    function _settleAuction() internal {
        Auction memory _auction = auctionStorage;

        require(_auction.startTime != 0, "Auction hasn't begun");
        require(!_auction.settled, 'Auction has already been settled');
        require(block.timestamp >= _auction.endTime, "Auction hasn't completed");

        auctionStorage.settled = true;

        if (_auction.bidder == address(0)) {
            token.burn(_auction.tokenId);
        } else {
            token.transferFrom(address(this), _auction.bidder, _auction.tokenId);
        }

        if (_auction.amount > 0) {
            _safeTransferETHWithFallback(splitter, _auction.amount);
        }

        emit AuctionSettled(_auction.tokenId, _auction.bidder, _auction.amount);
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as WETH.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(WETH).deposit{ value: amount }();
            IERC20(WETH).transfer(to, amount);
        }
    }

    /**
     * @notice Transfer ETH and return the success status.
     * @dev This function only forwards 30,000 gas to the callee.
     */
    function _safeTransferETH(address to, uint256 value) internal returns (bool) {
        bool success;
        assembly {
            success := call(30000, to, value, 0, 0, 0, 0)
        }
        return success;
    }
}
