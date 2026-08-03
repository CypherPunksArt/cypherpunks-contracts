// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";
import {Handler} from "./Handler.sol";
import {RevertOnReceiveBidder} from "../adversarial/Bidders.sol";

/// I8 — Settle liveness. Once ended, settlement succeeds for any caller, in
/// every reachable state, including paused, including hostile top bidder.
contract InvariantI8_SettleLiveness is Fixture {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(ah, token, guardian);
        targetContract(address(handler));
    }

    /// The handler attempts every due settlement it encounters and counts
    /// failures; any failure is an I8 violation.
    function invariant_I8_NoDueSettlementEverFails() public view {
        assertEq(handler.failedDueSettlements(), 0, "a due settlement reverted");
    }

    // ------------------------- deterministic scenario matrix (doc SS09) ----

    function test_I8_SettleByArbitraryCaller(address caller) public {
        vm.assume(caller != address(0));
        bidAs(makeAddr("bidder"), 1 ether);
        warpPastEnd();
        vm.prank(caller);
        ah.settleCurrentAndCreateNewAuction();
        assertEq(token.ownerOf(1), makeAddr("bidder"));
    }

    function test_I8_SettleWhilePaused() public {
        bidAs(makeAddr("bidder"), 1 ether);
        vm.prank(guardian);
        ah.pause();
        warpPastEnd();
        // settlement is permissionless while paused (doc SS01)
        vm.prank(makeAddr("randomSettler"));
        ah.settleAuction();
        assertEq(token.ownerOf(1), makeAddr("bidder"));
        assertEq(splitterAddr.balance, 1 ether, "proceeds routed while paused");
    }

    function test_I8_SettleWithHostileTopBidder() public {
        RevertOnReceiveBidder hostile = new RevertOnReceiveBidder(ah);
        vm.deal(address(hostile), 1 ether);
        hostile.bid(ah.auction().tokenId, 1 ether);
        warpPastEnd();
        // ERC721 transferFrom runs no receiver hook; settle cannot be blocked
        ah.settleCurrentAndCreateNewAuction();
        assertEq(token.ownerOf(1), address(hostile));
    }

    function test_I8_SettleNoBids_BurnsAndChains() public {
        warpPastEnd();
        ah.settleCurrentAndCreateNewAuction();
        // token 1 burned (Nouns-verbatim no-bid outcome), auction 2 live
        vm.expectRevert();
        token.ownerOf(1);
        assertEq(ah.auction().tokenId, 2);
    }
}
