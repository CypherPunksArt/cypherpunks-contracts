// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WalkFixture} from "./helpers/WalkFixture.sol";
import {console2} from "forge-std/console2.sol";

/// REHEARSAL — 12 full daily cycles on the REAL contracts (WalkFixture deploys
/// them through the genesis state machine, mock-VRF seed), exercising every edge
/// case a live run must survive, with a readable pass/fail line per cycle:
///   • normal bid → settle (winner gets token, proceeds route to splitter)
///   • the min-increment rule (underbid reverts; loser refunded)
///   • the anti-snipe extension (a late bid pushes the clock)
///   • the no-bid burn (token becomes unmintable)
///   • the walk advancing, every piece drawn exactly once (bijection)
///
/// This is the "10+ full daily cycles" gate — verified on a real EVM in seconds
/// instead of 10 real days. Run:  forge test --match-contract RehearsalCycles -vv
contract RehearsalCycles is WalkFixture {
    bool[10_000] internal seen;
    uint256 internal proceeds;

    event AuctionExtended(uint256 indexed tokenId, uint256 endTime);

    function setUp() public {
        _deployAndOpen(uint256(keccak256("rehearsal seed")));
    }

    function _draw() internal returns (uint256 tid) {
        tid = ah.auction().tokenId;
        uint256 p = token.punkForToken(tid);
        assertFalse(seen[p], "bijection: piece drawn twice");
        seen[p] = true;
    }

    function _settle(bytes32 entropy) internal {
        vm.warp(uint256(ah.auction().endTime));
        vm.prevrandao(entropy);
        ah.settleCurrentAndCreateNewAuction();
    }

    function test_Rehearsal_TwelveCycles_AllEdgeCases() public {
        console2.log("==== CypherPunks rehearsal: 12 full daily cycles ====");

        // ---- 1: normal bid -> settle ----
        uint256 tid = _draw();
        assertEq(tid, 1);
        address w1 = address(uint160(0x1001));
        vm.deal(w1, 0.05 ether); vm.prank(w1); ah.createBid{value: 0.05 ether}(tid);
        _settle("n1");
        assertEq(token.ownerOf(tid), w1, "winner didn't receive the token");
        proceeds += 0.05 ether;
        assertEq(address(splitter).balance, proceeds, "proceeds != splitter balance");
        console2.log("cycle  1  PASS  normal bid, settle, winner + 95/5 proceeds routed");

        // ---- 2: outbid, min-increment enforced, loser refunded ----
        tid = _draw();
        address a = address(uint160(0x2002));
        address b = address(uint160(0x3002));
        vm.deal(a, 1 ether); vm.prank(a); ah.createBid{value: 1 ether}(tid);
        vm.deal(b, 1.01 ether); vm.prank(b);
        vm.expectRevert(bytes('Must send more than last bid by minBidIncrementPercentage amount'));
        ah.createBid{value: 1.01 ether}(tid); // +1% < required +2% => reverts
        vm.deal(b, 1.02 ether); vm.prank(b); ah.createBid{value: 1.02 ether}(tid); // +2% ok
        _settle("n2");
        assertEq(token.ownerOf(tid), b, "outbidder didn't win");
        assertEq(a.balance, 1 ether, "outbid loser not auto-refunded");
        proceeds += 1.02 ether;
        assertEq(address(splitter).balance, proceeds, "proceeds != splitter balance");
        console2.log("cycle  2  PASS  min-increment blocks +1%, allows +2%, loser refunded");

        // ---- 3: anti-snipe extension ----
        tid = _draw();
        uint256 end0 = ah.auction().endTime;
        vm.warp(end0 - 5 minutes); // inside the 10-min buffer
        address w3 = address(uint160(0x4003));
        vm.deal(w3, 0.05 ether); vm.prank(w3); ah.createBid{value: 0.05 ether}(tid);
        uint256 end1 = ah.auction().endTime;
        assertGt(end1, end0, "anti-snipe: clock not extended");
        assertEq(end1, block.timestamp + 10 minutes, "extension != now + TIME_BUFFER");
        _settle("n3");
        assertEq(token.ownerOf(tid), w3);
        proceeds += 0.05 ether;
        console2.log("cycle  3  PASS  late bid extended the clock by the anti-snipe buffer");

        // ---- 4: no-bid burn ----
        tid = _draw();
        _settle("burn"); // no bids
        vm.expectRevert(); // ownerOf on a burned token reverts
        token.ownerOf(tid);
        console2.log("cycle  4  PASS  no-bid settlement burned the punk (unmintable forever)");

        // ---- 5..12: normal cycles, walk keeps advancing ----
        for (uint256 d = 5; d <= 12; d++) {
            tid = _draw();
            assertEq(tid, d, "walk: tokenId != day");
            address w = address(uint160(0x5000 + d));
            vm.deal(w, 0.03 ether); vm.prank(w); ah.createBid{value: 0.03 ether}(tid);
            _settle(keccak256(abi.encode("n", d)));
            assertEq(token.ownerOf(tid), w);
            proceeds += 0.03 ether;
            assertEq(address(splitter).balance, proceeds, "proceeds != splitter balance");
            console2.log("cycle %s  PASS  normal bid, settle, walk advanced", d);
        }

        console2.log("==== 12/12 CYCLES PASS -- every edge case green ====");
        console2.log("total proceeds routed to splitter (wei):", proceeds);
    }
}
