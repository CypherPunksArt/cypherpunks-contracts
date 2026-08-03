// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture, WETHMock} from "../helpers/Fixture.sol";
import {
    RevertOnReceiveBidder,
    ReturnBombBidder,
    GasGrieferBidder,
    ReentrancyProber
} from "./Bidders.sol";

/// Adversarial bidder suite (doc §09): every bot attacks the refund path or
/// cadence; each test asserts the relevant I8/I9/I13 statements.
contract AdversarialBiddersTest is Fixture {
    // ---------------------------------------------------- revert-on-receive

    function test_RevertOnReceive_CannotBlockOutbid_I9() public {
        RevertOnReceiveBidder hostile = new RevertOnReceiveBidder(ah);
        vm.deal(address(hostile), 1 ether);
        hostile.bid(ah.auction().tokenId, 1 ether);

        // outbid succeeds; hostile refund lands as WETH, executes no code
        bidAs(makeAddr("honest"), 2 ether);
        assertEq(ah.auction().bidder, makeAddr("honest"));
        assertEq(WETHMock(payable(WETH)).balanceOf(address(hostile)), 1 ether, "refund as WETH");
        assertEq(address(ah).balance, 2 ether, "I7 after hostile refund");
    }

    // ------------------------------------------------------------ returnbomb

    function test_ReturnBomb_OutbidGasBounded_I9() public {
        ReturnBombBidder bomber = new ReturnBombBidder(ah);
        vm.deal(address(bomber), 1 ether);
        bomber.bid(ah.auction().tokenId, 1 ether);

        address honest = makeAddr("honest");
        vm.deal(honest, 2 ether);
        uint256 tokenId = ah.auction().tokenId;
        vm.prank(honest);
        uint256 gasBefore = gasleft();
        ah.createBid{value: 2 ether}(tokenId);
        uint256 used = gasBefore - gasleft();

        assertEq(ah.auction().bidder, honest);
        // 1 MiB returndata ignored by the verbatim assembly call: the outbid
        // costs ordinary gas, not megabytes of memory expansion
        assertLt(used, 200_000, "returnbomb leaked into bidder gas");
    }

    // ------------------------------------------------------------ gas griefer

    function test_GasGriefer_StipendContains_I9() public {
        GasGrieferBidder griefer = new GasGrieferBidder(ah);
        vm.deal(address(griefer), 1 ether);
        griefer.bid(ah.auction().tokenId, 1 ether);

        address honest = makeAddr("honest");
        vm.deal(honest, 2 ether);
        uint256 tokenId = ah.auction().tokenId;
        vm.prank(honest);
        uint256 gasBefore = gasleft();
        ah.createBid{value: 2 ether}(tokenId);
        uint256 used = gasBefore - gasleft();

        assertEq(ah.auction().bidder, honest);
        // grief burns at most the 30k stipend, then falls back to WETH
        assertLt(used, 250_000, "griefer consumed unbounded gas");
        assertEq(WETHMock(payable(WETH)).balanceOf(address(griefer)), 1 ether);
    }

    // ------------------------------------------------------------ reentrancy

    function test_ReentrancyProber_NoReentry_I7() public {
        ReentrancyProber prober = new ReentrancyProber(ah);
        vm.deal(address(prober), 1 ether);
        prober.bid(ah.auction().tokenId, 1 ether);

        bidAs(makeAddr("honest"), 2 ether);

        assertFalse(prober.reenteredBid(), "reentered createBid");
        assertFalse(prober.reenteredSettle(), "reentered settle");
        // state stayed coherent (I7)
        assertEq(address(ah).balance, 2 ether);
        assertEq(ah.auction().bidder, makeAddr("honest"));
    }

    // ---------------------------------------------------------- self-outbidder

    function test_SelfOutbidder_EscalationAndBalance_I7() public {
        address selfish = makeAddr("selfish");
        uint256 amount = 1 ether;
        for (uint256 i = 0; i < 10; i++) {
            bidAs(selfish, amount);
            // I7 after every self-outbid: exactly the top bid is held
            assertEq(address(ah).balance, amount, "I7 broken mid-loop");
            assertEq(ah.auction().bidder, selfish);
            // each next bid must escalate >= 2%
            amount = amount + (amount * 2) / 100;
        }
        // refunds all came back (as ETH — selfish is an EOA)
        assertEq(ah.auction().amount, (address(ah).balance));
    }

    // ------------------------------------------------------ snipe-reset spam

    function test_SnipeResetSpammer_ExtensionsExactThenSettles_I13_I8() public {
        address spammer = makeAddr("spammer");
        vm.warp(uint256(ah.auction().endTime) - 30); // inside the buffer

        uint256 amount = 1 ether;
        uint256 lastBid;
        for (uint256 i = 0; i < 20; i++) {
            bidAs(spammer, amount);
            lastBid = amount;
            // I13: every reset lands exactly at now + buffer
            assertEq(ah.auction().endTime, uint40(block.timestamp + 10 minutes));
            // ride to one second before the new end, spam again
            vm.warp(block.timestamp + 10 minutes - 1);
            amount = amount + (amount * 2) / 100 + 1;
        }

        // spam stops: auction ends and settles for anyone (I8)
        vm.warp(block.timestamp + 2);
        vm.prank(makeAddr("randomSettler"));
        ah.settleCurrentAndCreateNewAuction();
        assertEq(token.ownerOf(1), spammer);
        // I10 shape: exactly the hammer price reached the splitter
        assertEq(splitterAddr.balance, lastBid, "proceeds != hammer price");
        assertEq(ah.auction().tokenId, 2, "next auction did not open");
    }
}
