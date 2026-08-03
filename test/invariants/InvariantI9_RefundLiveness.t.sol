// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";
import {
    RevertOnReceiveBidder,
    ReturnBombBidder,
    GasGrieferBidder
} from "../adversarial/Bidders.sol";

/// I9 — Refund liveness.
/// No refund recipient can cause a bid to revert or cost the new bidder
/// unbounded gas. (Adversarial bidder suite.)
///
/// This file asserts I9 through an invariant harness: an adversarial bot is
/// installed as the standing top bidder, then a fuzzed honest bidder must
/// always be able to outbid it within a bounded gas budget. Scenario-level
/// coverage lives in test/adversarial/AdversarialBidders.t.sol.
contract InvariantI9_RefundLiveness is Fixture {
    RevertOnReceiveBidder internal reverter;
    ReturnBombBidder internal bomber;
    GasGrieferBidder internal griefer;

    function setUp() public override {
        super.setUp();
        reverter = new RevertOnReceiveBidder(ah);
        bomber = new ReturnBombBidder(ah);
        griefer = new GasGrieferBidder(ah);
    }

    /// For each hostile standing bidder, an honest outbid always succeeds and
    /// the new bidder's gas stays bounded (the returnbomb/griefer cannot leak
    /// into the outbid). Refund lands as WETH; the bid path never reverts.
    function _assertHonestOutbidBounded(address hostile, uint256 hostileBid, uint256 honestBid)
        internal
    {
        // hostile takes the lead
        vm.deal(hostile, hostileBid);
        (bool ok,) = hostile.call(
            abi.encodeWithSignature("bid(uint256,uint256)", ah.auction().tokenId, hostileBid)
        );
        assertTrue(ok, "hostile bid setup failed");

        address honest = makeAddr("honest");
        uint256 tokenId = ah.auction().tokenId;
        vm.deal(honest, honestBid);
        vm.prank(honest);
        uint256 gasBefore = gasleft();
        ah.createBid{value: honestBid}(tokenId);
        uint256 used = gasBefore - gasleft();

        assertEq(ah.auction().bidder, honest, "honest outbid failed (I9 refund liveness)");
        assertLt(used, 300_000, "refund recipient leaked unbounded gas into bidder");
    }

    function testFuzz_I9_RevertOnReceive(uint256 hb, uint256 nb) public {
        uint256 hostileBid = bound(hb, 0.001 ether, 10 ether);
        uint256 honestBid = bound(nb, hostileBid + 0.001 ether + (hostileBid * 2) / 100, 30 ether);
        _assertHonestOutbidBounded(address(reverter), hostileBid, honestBid);
    }

    function testFuzz_I9_ReturnBomb(uint256 hb, uint256 nb) public {
        uint256 hostileBid = bound(hb, 0.001 ether, 10 ether);
        uint256 honestBid = bound(nb, hostileBid + 0.001 ether + (hostileBid * 2) / 100, 30 ether);
        _assertHonestOutbidBounded(address(bomber), hostileBid, honestBid);
    }

    function testFuzz_I9_GasGriefer(uint256 hb, uint256 nb) public {
        uint256 hostileBid = bound(hb, 0.001 ether, 10 ether);
        uint256 honestBid = bound(nb, hostileBid + 0.001 ether + (hostileBid * 2) / 100, 30 ether);
        _assertHonestOutbidBounded(address(griefer), hostileBid, honestBid);
    }
}
