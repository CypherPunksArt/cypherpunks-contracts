// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenHarness} from "./TokenHarness.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";
import {CypherPunksSplitter} from "../../src/Splitter.sol";

/// Minimal WETH mock, etched at the mainnet canonical address in tests so the
/// hardcoded fallback path is exercised without a fork.
contract WETHMock {
    mapping(address => uint256) public balanceOf;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function withdraw(uint256 value) external {
        balanceOf[msg.sender] -= value;
        (bool ok,) = msg.sender.call{value: value}("");
        require(ok);
    }

    receive() external payable {}
}

/// Shared deployment fixture: WETH etched, Token deployed against the
/// precomputed AuctionHouse address (both immutable, no setters), genesis
/// state machine run, auction #1 opened.
abstract contract Fixture is Test {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    TokenHarness internal token;
    CypherPunksAuctionHouse internal ah;
    CypherPunksSplitter internal splitter;

    address internal guardian = makeAddr("pauseGuardian");
    address internal artist = makeAddr("artistTreasury");
    address internal team = makeAddr("teamTreasury");
    address internal companyPayee = makeAddr("companyPayee");
    address internal artistPayee = makeAddr("artistPayee");
    address internal designerPayee = makeAddr("designerPayee");
    address internal splitterAddr; // the deployed CypherPunksSplitter

    function setUp() public virtual {
        // canonical WETH exists in every test run
        WETHMock impl = new WETHMock();
        vm.etch(WETH, address(impl).code);

        splitter = new CypherPunksSplitter(payable(companyPayee), payable(artistPayee), payable(designerPayee), makeAddr("payeeAdmin"));
        splitterAddr = address(splitter);

        // circular immutables: Token needs the AH address at construction
        uint64 nonce = vm.getNonce(address(this));
        address predictedAH = vm.computeCreateAddress(address(this), nonce + 1);
        token = new TokenHarness(predictedAH, artist, team, makeAddr("vrfCoordinator"));
        ah = new CypherPunksAuctionHouse(token, splitterAddr, guardian);
        assertEq(address(ah), predictedAH, "nonce prediction drifted");

        // genesis state machine (I17 steps seed..3), then auction #1 (step 4)
        token.writeSeedForTest(uint256(keccak256("phase3 fixture seed")));
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();
        ah.startAuctions();
    }

    // ------------------------------------------------------------- helpers

    function currentAuction() internal view returns (CypherPunksAuctionHouse.Auction memory) {
        return ah.auction();
    }

    /// Smallest valid next bid per the Rev 2 rule:
    /// opening bid ≥ reserve (0); outbids need max(2%, MIN_BID_STEP) more.
    function minNextBid() internal view returns (uint256) {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.bidder == address(0)) return 0;
        uint256 pct = (uint256(a.amount) * 2) / 100;
        uint256 inc = pct > 0.001 ether ? pct : 0.001 ether;
        return uint256(a.amount) + inc;
    }

    function bidAs(address who, uint256 value) internal {
        // hoist the id read: vm.prank binds to the NEXT external call, and an
        // inline ah.auction() argument would consume it
        uint256 tokenId = ah.auction().tokenId;
        vm.deal(who, value);
        vm.prank(who);
        ah.createBid{value: value}(tokenId);
    }

    function warpPastEnd() internal {
        vm.warp(uint256(ah.auction().endTime));
    }
}
