// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "./helpers/Fixture.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// Pause semantics per doc §01/§06: pause is instant and guardian-only and
/// halts creation of the NEXT auction only; in-flight bidding and settlement
/// are unaffected; unpause sits behind a 48h timelock and is executable by
/// anyone once matured. Also pins I11's privilege surface shape.
contract PauseSemanticsTest is Fixture {
    // ------------------------------------------------------------ privilege

    function testFuzz_PauseOnlyGuardian(address caller) public {
        vm.assume(caller != guardian);
        vm.prank(caller);
        vm.expectRevert(bytes('not guardian'));
        ah.pause();
    }

    function testFuzz_ScheduleUnpauseOnlyGuardian(address caller) public {
        vm.assume(caller != guardian);
        vm.prank(guardian);
        ah.pause();
        vm.prank(caller);
        vm.expectRevert(bytes('not guardian'));
        ah.scheduleUnpause();
    }

    // -------------------------------------------------------- while paused

    function test_Paused_InFlightBiddingUnaffected() public {
        bidAs(makeAddr("before"), 1 ether);
        vm.prank(guardian);
        ah.pause();
        // bidding on the live auction continues while paused
        bidAs(makeAddr("during"), 2 ether);
        assertEq(ah.auction().bidder, makeAddr("during"));
    }

    function test_Paused_SettlementSucceeds_NoNextAuction() public {
        bidAs(makeAddr("bidder"), 1 ether);
        vm.prank(guardian);
        ah.pause();
        warpPastEnd();

        // chained entrypoint is closed while paused
        vm.expectRevert();
        ah.settleCurrentAndCreateNewAuction();

        // pause-path settlement is permissionless and succeeds
        vm.prank(makeAddr("anyone"));
        ah.settleAuction();
        assertEq(token.ownerOf(1), makeAddr("bidder"));
        assertEq(splitterAddr.balance, 1 ether);

        // no next auction was created: pause halts creation only
        assertTrue(ah.auction().settled);
        assertEq(ah.auction().tokenId, 1);
    }

    // ------------------------------------------------------------- timelock

    function test_Unpause_RequiresScheduleThenDelay() public {
        vm.prank(guardian);
        ah.pause();

        // cannot unpause unscheduled
        vm.expectRevert(bytes('unpause not scheduled'));
        ah.unpause();

        vm.prank(guardian);
        ah.scheduleUnpause();

        // one second early: still locked
        vm.warp(block.timestamp + 48 hours - 1);
        vm.expectRevert(bytes('timelock not elapsed'));
        ah.unpause();

        // matured: anyone executes
        vm.warp(block.timestamp + 1);
        vm.prank(makeAddr("anyone"));
        ah.unpause();
        assertFalse(ah.paused());
    }

    function test_Unpause_ResumesCadenceAfterPausedSettlement() public {
        bidAs(makeAddr("bidder"), 1 ether);
        vm.prank(guardian);
        ah.pause();
        warpPastEnd();
        ah.settleAuction(); // settled while paused; no successor

        vm.prank(guardian);
        ah.scheduleUnpause();
        vm.warp(block.timestamp + 48 hours);
        ah.unpause();

        // unpause opened the next auction (Nouns pattern, genesis-gated)
        assertEq(ah.auction().tokenId, 2);
        assertFalse(ah.auction().settled);
    }

    function test_Repause_ClearsPendingUnpauseSchedule() public {
        vm.prank(guardian);
        ah.pause();
        vm.prank(guardian);
        ah.scheduleUnpause();

        // guardian re-pauses (already paused — clears the schedule)
        vm.prank(guardian);
        ah.pause();

        vm.warp(block.timestamp + 48 hours + 1);
        vm.expectRevert(bytes('unpause not scheduled'));
        ah.unpause();
    }

    // --------------------------------------------------------------- events

    function test_UnpauseScheduled_EventEmitted() public {
        vm.prank(guardian);
        ah.pause();
        vm.prank(guardian);
        vm.expectEmit(address(ah));
        emit UnpauseScheduled(block.timestamp + 48 hours);
        ah.scheduleUnpause();
    }

    function test_UnpauseCancelled_EventEmittedOnRepause() public {
        vm.prank(guardian);
        ah.pause();
        vm.prank(guardian);
        ah.scheduleUnpause();

        vm.prank(guardian);
        vm.expectEmit(address(ah));
        emit UnpauseCancelled();
        ah.pause();
    }

    function test_NoCancelEvent_WhenNothingScheduled() public {
        vm.recordLogs();
        vm.prank(guardian);
        ah.pause();
        // only Pausable's Paused event; no phantom UnpauseCancelled
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics[0] != keccak256("UnpauseCancelled()"),
                "cancel event without a schedule"
            );
        }
    }

    // matching event declarations for expectEmit
    event UnpauseScheduled(uint256 executableAt);
    event UnpauseCancelled();

    // ------------------------------------------------------- genesis gating

    function test_StartAuctions_OnceOnly() public {
        vm.expectRevert(bytes('auctions already started'));
        ah.startAuctions();
    }
}
