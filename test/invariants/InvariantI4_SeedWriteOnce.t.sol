// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CypherPunksToken} from "../../src/Token.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";
import {CypherPunksSplitter} from "../../src/Splitter.sol";
import {IDescriptor} from "../../src/interfaces/IDescriptor.sol";
import {VRFCoordinatorV2PlusMock} from "../helpers/VRFCoordinatorV2PlusMock.sol";
import {WETHMock} from "../helpers/Fixture.sol";

/// I4 — Seed write-once, draw-once.
/// After first fulfillment, no path alters the seed or re-runs the reserved
/// draw; after each settlement, no path re-draws that day's piece.
contract InvariantI4_SeedWriteOnce is Test {
    VRFCoordinatorV2PlusMock internal coord;
    CypherPunksToken internal token;
    CypherPunksAuctionHouse internal ah;

    address internal artist = makeAddr("artistTreasury");
    address internal team = makeAddr("teamTreasury");

    function setUp() public {
        WETHMock impl = new WETHMock();
        vm.etch(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, address(impl).code);
        coord = new VRFCoordinatorV2PlusMock();
        CypherPunksSplitter s = new CypherPunksSplitter(payable(makeAddr("c")), payable(makeAddr("a")), payable(makeAddr("d")), makeAddr("padmin"));
        uint64 nonce = vm.getNonce(address(this));
        address predictedAH = vm.computeCreateAddress(address(this), nonce + 1);
        token = new CypherPunksToken(
            predictedAH, artist, team, address(coord),
            keccak256("kh"), 1, IDescriptor(address(0))
        );
        ah = new CypherPunksAuctionHouse(token, address(s), makeAddr("guardian"));
    }

    // ---------------------------------------------- seed alter-once (I4a)

    function test_I4_DoubleFulfillmentReverts() public {
        uint256 id = token.requestSeed();
        coord.fulfill(id, 111);
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        coord.fulfill(id, 222);
        assertEq(token.seed(), 111);
    }

    /// M-01 (audit Rev 12): after a reRequest only the most recent request may
    /// fulfill — a stale request delivered late reverts, so the operator's fresh
    /// request is the one that seeds, not whichever word arrives first.
    function test_I4_OnlyMostRecentRequestFulfills() public {
        uint256 id1 = token.requestSeed();
        vm.warp(block.timestamp + 7 days);
        uint256 id2 = token.reRequest();
        vm.expectRevert(CypherPunksToken.UnknownRequest.selector);
        coord.fulfill(id1, 777);
        coord.fulfill(id2, 888);
        assertEq(token.seed(), 888);
    }

    function test_I4_ZeroWordFulfillment_SeedClosed() public {
        uint256 id = token.requestSeed();
        coord.fulfill(id, 0);
        assertTrue(token.seedFulfilled());
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        coord.fulfill(id, 999);
    }

    // --------------------------------------------- reserved draw-once (I4a)

    /// The reserved draw runs exactly once: blob + both tail mints are each
    /// single-shot, so the reserved sets can never be recomputed into state.
    function test_I4_ReservedDrawRunsOnce() public {
        uint256 id = token.requestSeed();
        coord.fulfill(id, uint256(keccak256("seed")));
        token.materializeBlob();
        vm.expectRevert(CypherPunksToken.BlobAlreadyMaterialized.selector);
        token.materializeBlob();
        token.mintArtistTail();
        vm.expectRevert(CypherPunksToken.ArtistTailAlreadyMinted.selector);
        token.mintArtistTail();
        token.mintTeamTail();
        vm.expectRevert(CypherPunksToken.TeamTailAlreadyMinted.selector);
        token.mintTeamTail();
    }

    // ------------------------------------------------ daily draw-once (I4b)

    /// After a settlement mints token N, no path re-draws or re-mints N:
    /// mintNext strictly increments publicMinted, so N is permanent.
    function test_I4_DailyDrawOncePerSettlement() public {
        uint256 id = token.requestSeed();
        coord.fulfill(id, uint256(keccak256("seed2")));
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();
        ah.startAuctions();

        uint256 piece1 = token.punkForToken(1);
        // settle day 1 → mints/draws day 2
        vm.warp(block.timestamp + 24 hours);
        ah.settleCurrentAndCreateNewAuction();
        // token 1's piece is fixed forever; day 2 is its own token/draw
        assertEq(token.punkForToken(1), piece1, "day-1 piece re-drawn");
        assertEq(ah.auction().tokenId, 2, "settlement must advance to a new token");
        assertEq(token.publicMinted(), 2, "publicMinted strictly advanced");
        // settle day 2 → day 3; ids never repeat
        vm.warp(block.timestamp + 24 hours);
        ah.settleCurrentAndCreateNewAuction();
        assertEq(ah.auction().tokenId, 3);
        assertEq(token.punkForToken(1), piece1, "day-1 piece still fixed");
    }
}
