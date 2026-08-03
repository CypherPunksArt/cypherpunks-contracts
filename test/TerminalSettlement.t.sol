// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WalkFixture} from "./helpers/WalkFixture.sol";

/// F1 (audit) — the terminal (9,800th) settlement fires AuctionWalkComplete and
/// parks the walk permanently: no #9,801 is created, and no entrypoint (settle,
/// startAuctions, or a full guardian pause -> scheduleUnpause -> matured unpause)
/// can reopen it. The fuzzer cannot reach this depth, so this pins it explicitly.
///
/// RUN TIER: WALK (slow) — drives the full 9,800-settlement walk, like
/// InvariantI1_Bijection.
contract TerminalSettlement is WalkFixture {
    uint256 internal constant PUBLIC_COUNT = 9_800;

    event AuctionWalkComplete();

    function setUp() public {
        _deployAndOpen(uint256(keccak256("terminal walk seed")));
    }

    /// forge-config: default.isolate = false
    function test_TerminalSettlement_EmitsWalkCompleteAndParks() public {
        // drive days 1..9,799 with a minimal opening bid each
        for (uint256 day = 1; day < PUBLIC_COUNT; day++) {
            address bidder = address(uint160(0x20000 + day));
            vm.deal(bidder, 0.001 ether);
            vm.prank(bidder);
            ah.createBid{value: 0.001 ether}(day);
            vm.warp(uint256(ah.auction().endTime));
            vm.prevrandao(keccak256(abi.encode("t", day)));
            ah.settleCurrentAndCreateNewAuction();
        }

        // day 9,800 — the final auction
        assertEq(ah.auction().tokenId, PUBLIC_COUNT, "not on the final day");
        address last = address(uint160(0x99999));
        vm.deal(last, 0.001 ether);
        vm.prank(last);
        ah.createBid{value: 0.001 ether}(PUBLIC_COUNT);
        vm.warp(uint256(ah.auction().endTime));
        vm.prevrandao(keccak256("final"));

        // AuctionWalkComplete is emitted on the final settle
        vm.expectEmit(false, false, false, true);
        emit AuctionWalkComplete();
        ah.settleCurrentAndCreateNewAuction();

        // pool exhausted; the walk is parked at 9,800 (no #9,801 created)
        assertEq(token.poolRemaining(), 0, "pool not exhausted");
        assertEq(ah.auction().tokenId, PUBLIC_COUNT, "auction advanced past 9,800");
        assertTrue(ah.auction().settled, "final auction not settled");

        // no entrypoint reopens the walk
        vm.expectRevert();
        ah.settleCurrentAndCreateNewAuction();
        vm.expectRevert();
        ah.startAuctions();

        // even a full guardian pause -> scheduleUnpause -> matured unpause
        // creates NO new auction
        vm.prank(guardian);
        ah.pause();
        vm.prank(guardian);
        ah.scheduleUnpause();
        vm.warp(block.timestamp + 48 hours + 1);
        ah.unpause();
        assertEq(ah.auction().tokenId, PUBLIC_COUNT, "unpause created a new auction");
        assertTrue(ah.auction().settled, "unpause reopened the walk");
    }
}
