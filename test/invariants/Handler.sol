// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {TokenHarness} from "../helpers/TokenHarness.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";
import {
    RevertOnReceiveBidder,
    ReturnBombBidder,
    GasGrieferBidder
} from "../adversarial/Bidders.sol";

/// Fuzzed-actor handler for the invariant suites: EOA bidders, hostile
/// contract bidders (INV-C6/INV-D2 WETH + gas-cap paths), settlers, time warps,
/// pause/unpause/repause-cancel.
contract Handler is CommonBase, StdCheats, StdUtils {
    CypherPunksAuctionHouse public ah;
    TokenHarness public token;
    address public guardian;
    RevertOnReceiveBidder public hostile;
    ReturnBombBidder public bomber;
    GasGrieferBidder public griefer;
    /// Rejects ERC721 receiver hooks — settle uses transferFrom (not safe),
    /// so this must never brick INV-D1. Counter tracks successful settles.
    RejectERC721Bidder public rejectNft;
    uint256 public hostileNftSettlements;

    address[5] public actors;
    uint256 public settlements;
    uint256 public failedDueSettlements; // INV-D1 probe: must stay zero
    uint256 public pausedSettlements; // INV-D1: settleWhilePaused path exercised
    uint256 public repauseCancels; // INV-H2: schedule cleared by re-pause

    constructor(CypherPunksAuctionHouse _ah, TokenHarness _token, address _guardian) {
        ah = _ah;
        token = _token;
        guardian = _guardian;
        hostile = new RevertOnReceiveBidder(_ah);
        bomber = new ReturnBombBidder(_ah);
        griefer = new GasGrieferBidder(_ah);
        rejectNft = new RejectERC721Bidder(_ah);
        for (uint256 i = 0; i < 5; i++) {
            actors[i] = address(uint160(uint256(keccak256(abi.encode("actor", i)))));
        }
    }

    function bid(uint256 actorSeed, uint256 amountSeed) external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled || block.timestamp >= a.endTime) return;

        uint256 amount = _boundBid(a, amountSeed);
        address actor = actors[actorSeed % 5];
        vm.deal(actor, amount);
        vm.prank(actor);
        ah.createBid{value: amount}(a.tokenId);
    }

    /// Contract bidder that reverts on ETH receive — forces WETH refund path (INV-C6/INV-D2).
    function bidHostile(uint256 amountSeed) external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled || block.timestamp >= a.endTime) return;

        uint256 amount = _boundBid(a, amountSeed);
        // skip dust opening: hostile needs a positive refund to exercise WETH
        if (amount == 0) amount = 0.001 ether;
        vm.deal(address(hostile), amount);
        hostile.bid(a.tokenId, amount);
    }

    /// Return-bomb standing bidder — INV-D2 gas cap must contain returndata copy.
    function bidReturnBomb(uint256 amountSeed) external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled || block.timestamp >= a.endTime) return;

        uint256 amount = _boundBid(a, amountSeed);
        if (amount == 0) amount = 0.001 ether;
        vm.deal(address(bomber), amount);
        bomber.bid(a.tokenId, amount);
    }

    /// Gas-griefer standing bidder — INV-D2 30k stipend must contain the burn.
    function bidGasGriefer(uint256 amountSeed) external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled || block.timestamp >= a.endTime) return;

        uint256 amount = _boundBid(a, amountSeed);
        if (amount == 0) amount = 0.001 ether;
        vm.deal(address(griefer), amount);
        griefer.bid(a.tokenId, amount);
    }

    /// Top bidder that rejects ERC721 receiver hooks. Settle must still
    /// succeed via transferFrom (INV-D1 matrix in fuzz).
    function bidRejectNft(uint256 amountSeed) external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled || block.timestamp >= a.endTime) return;

        uint256 amount = _boundBid(a, amountSeed);
        if (amount == 0) amount = 0.001 ether;
        vm.deal(address(rejectNft), amount);
        rejectNft.bid(a.tokenId, amount);
    }

    function warpWithinAuction(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1, 6 hours));
    }

    function warpPastEnd() external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled) return;
        if (block.timestamp < a.endTime) vm.warp(uint256(a.endTime));
    }

    /// Settle whenever due — through the paused or unpaused entrypoint.
    /// A due settlement that reverts is an INV-D1 violation, counted, never
    /// swallowed into fail_on_revert noise.
    function settle() external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled || block.timestamp < a.endTime) return;

        address priorBidder = a.bidder;
        bool ok;
        if (ah.paused()) {
            try ah.settleAuction() {
                ok = true;
            } catch {}
        } else {
            try ah.settleCurrentAndCreateNewAuction() {
                ok = true;
            } catch {}
        }
        if (ok) {
            settlements++;
            if (priorBidder == address(rejectNft)) hostileNftSettlements++;
        } else {
            failedDueSettlements++;
        }
    }

    /// Dedicated INV-D1 path: pause (if needed), warp past end, settleAuction.
    function settleWhilePaused() external {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        if (a.startTime == 0 || a.settled) return;

        if (!ah.paused()) {
            vm.prank(guardian);
            ah.pause();
        }
        if (block.timestamp < a.endTime) vm.warp(uint256(a.endTime));

        address priorBidder = a.bidder;
        try ah.settleAuction() {
            settlements++;
            pausedSettlements++;
            if (priorBidder == address(rejectNft)) hostileNftSettlements++;
        } catch {
            failedDueSettlements++;
        }
    }

    function pauseByGuardian() external {
        if (ah.paused()) return;
        vm.prank(guardian);
        ah.pause();
    }

    function scheduleAndExecuteUnpause() external {
        if (!ah.paused()) return;
        vm.prank(guardian);
        ah.scheduleUnpause();
        vm.warp(block.timestamp + ah.UNPAUSE_DELAY());
        ah.unpause();
    }

    /// INV-H2: pause → schedule → re-pause clears the pending unpause.
    function repauseCancel() external {
        if (!ah.paused()) {
            vm.prank(guardian);
            ah.pause();
        }
        vm.prank(guardian);
        ah.scheduleUnpause();
        vm.prank(guardian);
        ah.pause();
        repauseCancels++;
    }

    function _boundBid(CypherPunksAuctionHouse.Auction memory a, uint256 amountSeed)
        internal
        pure
        returns (uint256 amount)
    {
        uint256 floor;
        if (a.bidder == address(0)) {
            floor = 0;
        } else {
            uint256 pct = (uint256(a.amount) * 2) / 100;
            uint256 inc = pct > 0.001 ether ? pct : 0.001 ether;
            floor = uint256(a.amount) + inc;
        }
        amount = bound(amountSeed, floor, floor + 10 ether);
    }
}

/// Bids normally; rejects ERC721 receiver hooks. Documents that settle uses
/// transferFrom (not safeTransferFrom) so a rejecting recipient cannot brick INV-D1.
contract RejectERC721Bidder {
    CypherPunksAuctionHouse internal ah;

    constructor(CypherPunksAuctionHouse _ah) {
        ah = _ah;
    }

    function bid(uint256 tokenId, uint256 value) external {
        ah.createBid{value: value}(tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert("reject NFT");
    }

    receive() external payable {}
}
