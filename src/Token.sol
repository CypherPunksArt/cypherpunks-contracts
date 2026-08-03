// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ReservedDraw} from "./lib/ReservedDraw.sol";
import {DailyDraw} from "./lib/DailyDraw.sol";
import {SSTORE2} from "./lib/SSTORE2.sol";
import {IDescriptor} from "./interfaces/IDescriptor.sol";
import {IVRFCoordinatorV2Plus, VRFV2PlusRequest} from "./interfaces/IVRFCoordinatorV2Plus.sol";

/// @title CypherPunksToken
/// @notice ERC-721 for the 10,000 CypherPunks. Boring, standards-clean 721
///         surface (doc §02 row 2). Token ID = auction sequence; design-piece
///         number is a separate attribute (doc §04 ID-semantics note).
///
///         Genesis is a strictly ordered, permissionless, idempotent state
///         machine (I17):
///           seed (VRF, write-once)
///             → (1) materializeBlob(): publicPiece table computed ONCHAIN
///                   from the seed and written once via SSTORE2 (I16)
///             → (2) mintArtistTail(): 100 pieces → token IDs 9,801–9,900
///             → (3) mintTeamTail():   100 pieces → token IDs 9,901–10,000
///             → (4) auction #1 (AuctionHouse; gated on genesisComplete())
///
///         No owner. No setters. The only mint paths are the two genesis
///         tail batches and mintNext() from the immutable auction house (I5).
/// @dev Zero secondary royalties (doc §01 Rev 3): no ERC-2981 anywhere —
///      same posture as CryptoPunks and Nouns. The artist's stream is 5% of
///      primary via the immutable splitter.
contract CypherPunksToken is ERC721 {
    using DailyDraw for DailyDraw.Pool;
    using Strings for uint256;

    // ------------------------------------------------------------ constants

    uint256 public constant TOTAL_SUPPLY = 10_000;
    uint256 public constant PUBLIC_COUNT = 9_800;
    uint256 public constant ARTIST_COUNT = 100;
    uint256 public constant TEAM_COUNT = 100;
    /// @dev Public auction token IDs are 1…9,800; tails follow (doc §04).
    uint256 public constant ARTIST_ID_START = 9_801;
    uint256 public constant TEAM_ID_START = 9_901;

    // ----------------------------------------------------------- immutables

    /// @notice The only address allowed to mint public tokens.
    address public immutable auctionHouse;
    /// @notice Genesis tail recipients (doc §04). Immutable, set at deploy.
    address public immutable artistTreasury;
    address public immutable teamTreasury;
    /// @notice Renderer, locked at deploy (Phase 8: src/Descriptor.sol,
    ///         deployed first per the pinned order; production validate
    ///         rejects a zero descriptor). The minimal-data-URI fallback
    ///         in tokenURI() exists only for test fixtures wiring address(0).
    IDescriptor public immutable descriptor;

    // --------------------------------------------------- VRF v2.5 (doc §05)

    /// @notice Chainlink VRF v2.5 coordinator (mainnet), immutable.
    address public immutable vrfCoordinator;
    bytes32 public immutable vrfKeyHash;
    uint256 public immutable vrfSubId;

    /// @dev Fulfillment only writes the seed — far below the v2.5 cap.
    uint32 public constant VRF_CALLBACK_GAS_LIMIT = 100_000;
    uint16 public constant VRF_REQUEST_CONFIRMATIONS = 6;
    /// @notice Stuck-request escape window (doc §05 "e.g. 7 days" — pinned).
    uint256 public constant RE_REQUEST_TIMEOUT = 7 days;

    // -------------------------------------------------------------- storage

    /// @notice Genesis VRF seed. Write-once, guarded by seedFulfilled — a
    ///         zero VRF word is a valid seed and cannot re-open the write
    ///         (doc §05 as amended).
    uint256 public seed;
    /// @notice True once fulfillRandomWords has written the seed.
    bool public seedFulfilled;
    /// @notice Timestamp of the latest seed request; zero = never requested.
    uint256 public lastSeedRequestAt;
    /// @dev Request ids this contract actually issued (provenance record).
    mapping(uint256 => bool) public seedRequestIssued;
    /// @notice The single request id currently eligible to fulfill the seed —
    ///         always the most recent request. A reRequest supersedes the prior
    ///         id, so a late fulfillment of a stale request can never win the
    ///         seed (audit M-01, Rev 12). Zero until the first request.
    uint256 public activeSeedRequestId;
    /// @notice SSTORE2 pointer to the 9,800-entry publicPiece table (I16).
    address public publicPieceBlob;
    /// @notice Genesis tail progress (0 or full count) — I17 stages 2 and 3.
    uint256 public artistMinted;
    uint256 public teamMinted;
    /// @notice Public tokens minted so far; token IDs are 1…publicMinted (I5).
    uint256 public publicMinted;

    /// @dev Daily-draw pool over publicPiece indices (doc §03).
    DailyDraw.Pool private _pool;
    /// @dev tokenId → design piece + 1 for public tokens (0 = unminted).
    mapping(uint256 => uint256) private _piecePlusOne;

    // --------------------------------------------------------------- events

    event SeedWritten(uint256 seed);
    event SeedRequested(uint256 indexed requestId, bool isReRequest);
    event BlobMaterialized(address pointer);
    event ArtistTailMinted(address to);
    event TeamTailMinted(address to);
    event PunkDrawn(uint256 indexed tokenId, uint256 indexed pieceId);

    // --------------------------------------------------------------- errors

    error ZeroAddress();
    error SeedAlreadySet();
    error SeedNotSet();
    error SeedAlreadyRequested();
    error SeedNotRequested();
    error ReRequestNotReady();
    error OnlyCoordinator();
    error UnknownRequest();
    error BlobAlreadyMaterialized();
    error BlobNotMaterialized();
    error ArtistTailAlreadyMinted();
    error ArtistTailPending();
    error TeamTailAlreadyMinted();
    error GenesisIncomplete();
    error OnlyAuctionHouse();
    error NonexistentToken();

    // ---------------------------------------------------------- constructor

    /// @param auctionHouse_ immutable minter of public tokens
    /// @param artistTreasury_ genesis recipient of token IDs 9,801–9,900
    /// @param teamTreasury_ genesis recipient of token IDs 9,901–10,000
    /// @param vrfCoordinator_ Chainlink VRF v2.5 coordinator (mainnet)
    /// @param vrfKeyHash_ VRF gas-lane key hash
    /// @param vrfSubId_ VRF v2.5 subscription id
    constructor(
        address auctionHouse_,
        address artistTreasury_,
        address teamTreasury_,
        address vrfCoordinator_,
        bytes32 vrfKeyHash_,
        uint256 vrfSubId_,
        IDescriptor descriptor_
    ) ERC721("CypherPunks", "PUNK") {
        if (
            auctionHouse_ == address(0) || artistTreasury_ == address(0)
                || teamTreasury_ == address(0) || vrfCoordinator_ == address(0)
        ) revert ZeroAddress();
        auctionHouse = auctionHouse_;
        artistTreasury = artistTreasury_;
        teamTreasury = teamTreasury_;
        vrfCoordinator = vrfCoordinator_;
        vrfKeyHash = vrfKeyHash_;
        vrfSubId = vrfSubId_;
        descriptor = descriptor_;
    }

    // ------------------------------------------------------- seed (write-once)

    /// @notice Request the genesis seed. Permissionless; only callable after
    ///         deployment (lock ordering by construction, doc §05); exactly
    ///         one live request path — re-requests only via reRequest().
    function requestSeed() external returns (uint256 requestId) {
        if (seedFulfilled) revert SeedAlreadySet();
        if (lastSeedRequestAt != 0) revert SeedAlreadyRequested();
        requestId = _requestSeed(false);
    }

    /// @notice Stuck-request escape (doc §05): permissionless — anyone, not
    ///         the team — once RE_REQUEST_TIMEOUT has passed since the last
    ///         request without fulfillment. Still write-once on fulfillment;
    ///         unreachable after fulfillment (no re-roll exists in bytecode).
    function reRequest() external returns (uint256 requestId) {
        if (seedFulfilled) revert SeedAlreadySet();
        if (lastSeedRequestAt == 0) revert SeedNotRequested();
        if (block.timestamp < lastSeedRequestAt + RE_REQUEST_TIMEOUT) revert ReRequestNotReady();
        requestId = _requestSeed(true);
    }

    function _requestSeed(bool isReRequest) private returns (uint256 requestId) {
        lastSeedRequestAt = block.timestamp;
        requestId = IVRFCoordinatorV2Plus(vrfCoordinator).requestRandomWords(
            VRFV2PlusRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubId,
                requestConfirmations: VRF_REQUEST_CONFIRMATIONS,
                callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                numWords: 1,
                // ExtraArgsV1: pay in LINK (nativePayment = false)
                extraArgs: abi.encodeWithSelector(
                    bytes4(keccak256("VRF ExtraArgsV1")), false
                )
            })
        );
        seedRequestIssued[requestId] = true;
        activeSeedRequestId = requestId;
        emit SeedRequested(requestId, isReRequest);
    }

    /// @notice VRF v2.5 fulfillment entrypoint (consumer surface, no owner —
    ///         the Chainlink consumer base is not inherited because it drags
    ///         in ConfirmedOwner; the coordinator check is reproduced here).
    /// @dev Writes the seed and does NOTHING else (doc §05: callback gas cap;
    ///      no minting, no blob work). Only the MOST RECENT request may fulfill:
    ///      a reRequest supersedes the prior id, so if a stale request is
    ///      delivered late the operator's fresh request is the one that seeds —
    ///      not whichever word happens to arrive first (audit M-01). Still
    ///      write-once thereafter: any later fulfillment reverts via _writeSeed.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != vrfCoordinator) revert OnlyCoordinator();
        if (requestId != activeSeedRequestId) revert UnknownRequest();
        _writeSeed(randomWords[0]);
    }

    /// @dev Doc §05: write-once via the seedFulfilled flag, so a zero VRF
    ///      word cannot leave the seed writable.
    function _writeSeed(uint256 word) internal {
        if (seedFulfilled) revert SeedAlreadySet();
        seedFulfilled = true;
        seed = word;
        emit SeedWritten(word);
    }

    // ------------------------------------- genesis state machine (I16, I17)

    /// @notice Step 1 — compute the publicPiece table onchain from the seed
    ///         and write it once as an SSTORE2 blob. Permissionless.
    /// @dev I16: the table is derived here, in this call, from the seed via
    ///      the same ReservedDraw the tail mints use. There is NO parameter
    ///      and NO code path that accepts an externally supplied table.
    function materializeBlob() external {
        if (!seedFulfilled) revert SeedNotSet();
        if (publicPieceBlob != address(0)) revert BlobAlreadyMaterialized();

        (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(seed);

        bool[] memory reserved = new bool[](TOTAL_SUPPLY);
        for (uint256 i = 0; i < ARTIST_COUNT; i++) {
            reserved[artist[i]] = true;
            reserved[team[i]] = true;
        }

        // publicPiece[i] = i-th design piece after removing the reserved 200,
        // packed big-endian uint16, 19,600 bytes total.
        bytes memory table = new bytes(PUBLIC_COUNT * 2);
        uint256 w = 0;
        for (uint256 piece = 0; piece < TOTAL_SUPPLY; piece++) {
            if (reserved[piece]) continue;
            table[w] = bytes1(uint8(piece >> 8));
            table[w + 1] = bytes1(uint8(piece & 0xFF));
            unchecked {
                w += 2;
            }
        }
        assert(w == PUBLIC_COUNT * 2);

        publicPieceBlob = SSTORE2.write(table);
        _pool.init(PUBLIC_COUNT);
        emit BlobMaterialized(publicPieceBlob);
    }

    /// @notice Step 2 — mint the artist 100 to the immutable artist address,
    ///         token IDs 9,801–9,900. Permissionless, once.
    function mintArtistTail() external {
        if (publicPieceBlob == address(0)) revert BlobNotMaterialized();
        if (artistMinted != 0) revert ArtistTailAlreadyMinted();
        artistMinted = ARTIST_COUNT;

        (uint16[100] memory artist,) = ReservedDraw.draw(seed);
        for (uint256 i = 0; i < ARTIST_COUNT; i++) {
            uint256 tokenId = ARTIST_ID_START + i;
            _piecePlusOne[tokenId] = uint256(artist[i]) + 1;
            _mint(artistTreasury, tokenId);
            emit PunkDrawn(tokenId, artist[i]);
        }
        emit ArtistTailMinted(artistTreasury);
    }

    /// @notice Step 3 — mint the team 100 to the immutable team address,
    ///         token IDs 9,901–10,000. Permissionless, once, after step 2.
    function mintTeamTail() external {
        if (artistMinted == 0) revert ArtistTailPending();
        if (teamMinted != 0) revert TeamTailAlreadyMinted();
        teamMinted = TEAM_COUNT;

        (, uint16[100] memory team) = ReservedDraw.draw(seed);
        for (uint256 i = 0; i < TEAM_COUNT; i++) {
            uint256 tokenId = TEAM_ID_START + i;
            _piecePlusOne[tokenId] = uint256(team[i]) + 1;
            _mint(teamTreasury, tokenId);
            emit PunkDrawn(tokenId, team[i]);
        }
        emit TeamTailMinted(teamTreasury);
    }

    /// @notice Step 4 gate — auction #1 is unreachable until steps 1–3 ran.
    function genesisComplete() public view returns (bool) {
        return teamMinted == TEAM_COUNT;
    }

    // ------------------------------------------------------- auction minting

    /// @notice Mint the next public token to `to`, drawing its design piece
    ///         from the pool in the same transaction (doc §03; I15).
    /// @dev Only the immutable auction house; only after genesis; IDs are
    ///      strictly sequential 1…9,800 (I5). Pool exhaustion reverts.
    function mintNext(address to) external returns (uint256 tokenId) {
        if (msg.sender != auctionHouse) revert OnlyAuctionHouse();
        if (!genesisComplete()) revert GenesisIncomplete();

        tokenId = ++publicMinted; // 1-based, strictly sequential
        uint256 index = _pool.drawNext(tokenId);
        uint256 pieceId = SSTORE2.readUint16(publicPieceBlob, index);
        _piecePlusOne[tokenId] = pieceId + 1;
        _mint(to, tokenId);
        emit PunkDrawn(tokenId, pieceId);
    }

    /// @notice Burn a public token — Nouns-verbatim no-bid settlement
    ///         outcome. Only the auction house, which only ever burns the
    ///         token it custodies for a zero-bid auction. The piece
    ///         assignment survives (I1: assigned exactly once).
    function burn(uint256 tokenId) external {
        if (msg.sender != auctionHouse) revert OnlyAuctionHouse();
        _burn(tokenId);
    }

    // -------------------------------------------------------------- lookups

    /// @notice Design piece for a minted token (doc: metadata `piece`).
    function punkForToken(uint256 tokenId) public view returns (uint256) {
        uint256 v = _piecePlusOne[tokenId];
        if (v == 0) revert NonexistentToken();
        return v - 1;
    }

    /// @notice i-th public design piece from the immutable blob (doc §03).
    function publicPieceAt(uint256 index) public view returns (uint256) {
        if (publicPieceBlob == address(0)) revert BlobNotMaterialized();
        return SSTORE2.readUint16(publicPieceBlob, index);
    }

    /// @notice Public pieces not yet drawn (9,800 → 0 over the walk).
    function poolRemaining() external view returns (uint256) {
        return _pool.remaining;
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 pieceId = punkForToken(tokenId);
        if (address(descriptor) != address(0)) {
            return descriptor.tokenURI(tokenId, pieceId);
        }
        // Test-fixture-only branch: the real Descriptor exists (Phase 8) and
        // production validate rejects a zero descriptor, so this placeholder
        // is unreachable in any production deployment.
        return string.concat(
            "data:application/json;utf8,",
            '{"name":"CypherPunk ',
            tokenId.toString(),
            '","piece":',
            pieceId.toString(),
            "}"
        );
    }

}
