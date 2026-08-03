// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture, WETHMock} from "../helpers/Fixture.sol";
import {RevertOnReceiveBidder} from "../adversarial/Bidders.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";

/// Deterministic side-effect pins for AuctionHouse value-moving paths.
/// Each test asserts one refund, settle, or splitter effect.
contract MutationSurvivorPoC is Fixture {
    // ------------------------------------------------ Group A — settle must run

    /// FINDING-MUT-001: settleCurrentAndCreateNewAuction must call _settleAuction.
    function test_PoC_MUT_001_SettleAndChain_TransfersMintAndPaysSplitter() public {
        address bidder = makeAddr("winner");
        uint256 hammer = 1 ether;
        bidAs(bidder, hammer);
        warpPastEnd();

        uint256 splitterBefore = splitterAddr.balance;
        uint256 ahBefore = address(ah).balance;

        vm.expectEmit(true, true, true, true);
        emit CypherPunksAuctionHouse.AuctionSettled(1, bidder, hammer);

        ah.settleCurrentAndCreateNewAuction();

        assertEq(token.ownerOf(1), bidder, "MUT-001: winner must own token");
        assertEq(splitterAddr.balance - splitterBefore, hammer, "MUT-001: splitter must get hammer");
        assertEq(address(ah).balance, ahBefore - hammer, "MUT-001: AH must release hammer");
        assertEq(ah.auction().tokenId, 2, "MUT-001: next auction must open");
    }

    /// FINDING-MUT-002: settleAuction must call _settleAuction while paused.
    function test_PoC_MUT_002_SettleWhilePaused_TransfersAndPaysSplitter() public {
        address bidder = makeAddr("winner");
        uint256 hammer = 1 ether;
        bidAs(bidder, hammer);

        vm.prank(guardian);
        ah.pause();
        warpPastEnd();

        uint256 splitterBefore = splitterAddr.balance;

        vm.expectEmit(true, true, true, true);
        emit CypherPunksAuctionHouse.AuctionSettled(1, bidder, hammer);

        ah.settleAuction();

        assertEq(token.ownerOf(1), bidder, "MUT-002: winner must own token");
        assertEq(splitterAddr.balance - splitterBefore, hammer, "MUT-002: splitter must get hammer");
        assertEq(address(ah).balance, 0, "MUT-002: AH must drain hammer");
    }

    // ------------------------------------------------ Group B — outbid must refund

    /// FINDING-MUT-003: createBid must refund the prior bidder on outbid.
    function test_PoC_MUT_003_Outbid_RefundsPriorBidder() public {
        address prior = makeAddr("prior");
        address next = makeAddr("next");
        uint256 priorBid = 1 ether;
        uint256 nextBid = 2 ether;

        bidAs(prior, priorBid);
        uint256 ethBefore = prior.balance;
        uint256 wethBefore = WETHMock(payable(WETH)).balanceOf(prior);

        bidAs(next, nextBid);

        uint256 ethCredit = prior.balance - ethBefore;
        uint256 wethCredit = WETHMock(payable(WETH)).balanceOf(prior) - wethBefore;
        assertEq(ethCredit + wethCredit, priorBid, "MUT-003: prior bidder must be made whole");
        assertEq(ah.auction().bidder, next);
        assertEq(address(ah).balance, nextBid, "MUT-003: AH holds only top bid");
    }

    // ------------------------------------------------ Group C — settle must pay splitter

    /// FINDING-MUT-004: _settleAuction must forward the hammer to the splitter.
    function test_PoC_MUT_004_Settle_ForwardsHammerToSplitter() public {
        address bidder = makeAddr("winner");
        uint256 hammer = 3 ether;
        bidAs(bidder, hammer);
        warpPastEnd();

        uint256 splitterBefore = splitterAddr.balance;
        ah.settleCurrentAndCreateNewAuction();

        assertEq(splitterAddr.balance - splitterBefore, hammer, "MUT-004: splitter delta must equal hammer");
        assertEq(address(ah).balance, 0, "MUT-004: AH must not retain hammer");
    }

    // ------------------------------------------------ Group D — ETH / WETH fallback branches

    /// FINDING-MUT-005: when ETH transfer succeeds, WETH fallback must not run.
    function test_PoC_MUT_005_EoaRefund_UsesEthNotWeth() public {
        address prior = makeAddr("eoaPrior");
        uint256 priorBid = 1 ether;
        bidAs(prior, priorBid);

        uint256 ethBefore = prior.balance;
        uint256 wethBefore = WETHMock(payable(WETH)).balanceOf(prior);
        uint256 wethSupplyBefore = address(WETH).balance;

        bidAs(makeAddr("next"), 2 ether);

        assertEq(prior.balance - ethBefore, priorBid, "MUT-005: EOA refund must be ETH");
        assertEq(WETHMock(payable(WETH)).balanceOf(prior), wethBefore, "MUT-005: EOA must not get WETH");
        assertEq(address(WETH).balance, wethSupplyBefore, "MUT-005: WETH deposit must not run");
    }

    /// FINDING-MUT-006: when ETH transfer fails, WETH fallback must run.
    function test_PoC_MUT_006_HostileRefund_FallsBackToWeth() public {
        RevertOnReceiveBidder hostile = new RevertOnReceiveBidder(ah);
        vm.deal(address(hostile), 1 ether);
        hostile.bid(ah.auction().tokenId, 1 ether);

        uint256 wethBefore = WETHMock(payable(WETH)).balanceOf(address(hostile));
        bidAs(makeAddr("next"), 2 ether);

        assertEq(
            WETHMock(payable(WETH)).balanceOf(address(hostile)) - wethBefore,
            1 ether,
            "MUT-006: hostile prior must get WETH fallback"
        );
        assertEq(address(hostile).balance, 0, "MUT-006: ETH path must not credit hostile");
    }
}
