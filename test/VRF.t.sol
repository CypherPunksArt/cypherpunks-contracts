// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CypherPunksToken} from "../src/Token.sol";
import {CypherPunksAuctionHouse} from "../src/AuctionHouse.sol";
import {CypherPunksSplitter} from "../src/Splitter.sol";
import {IDescriptor} from "../src/interfaces/IDescriptor.sol";
import {VRFCoordinatorV2PlusMock} from "./helpers/VRFCoordinatorV2PlusMock.sol";
import {WETHMock} from "./helpers/Fixture.sol";

/// VRF integration per doc §05 (Rev 3): one request ever, write-once
/// seed-only fulfillment, permissionless timed reRequest, lock ordering by
/// construction. Runs against the REAL CypherPunksToken (no test harness) so
/// the production seed path is what's exercised.
contract VRFTest is Test {
    VRFCoordinatorV2PlusMock internal coordinator;
    CypherPunksToken internal token;
    CypherPunksAuctionHouse internal ah;
    CypherPunksSplitter internal splitter;

    address internal artist = makeAddr("artistTreasury");
    address internal team = makeAddr("teamTreasury");
    address internal guardian = makeAddr("pauseGuardian");

    function setUp() public {
        WETHMock impl = new WETHMock();
        vm.etch(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, address(impl).code);

        coordinator = new VRFCoordinatorV2PlusMock();
        splitter = new CypherPunksSplitter(payable(makeAddr("companyPayee")), payable(makeAddr("artistPayee")), payable(makeAddr("designerPayee")), makeAddr("payeeAdmin"));

        uint64 nonce = vm.getNonce(address(this));
        address predictedAH = vm.computeCreateAddress(address(this), nonce + 1);
        token = new CypherPunksToken(
            predictedAH,
            artist,
            team,
            address(coordinator),
            keccak256("test gas lane key hash"), // placeholder key hash
            1,
            IDescriptor(address(0))
        );
        ah = new CypherPunksAuctionHouse(token, address(splitter), guardian);
        assertEq(address(ah), predictedAH);
    }

    // ------------------------------------------------------------- requests

    function testFuzz_RequestSeed_Permissionless(address caller) public {
        vm.assume(caller != address(0));
        vm.prank(caller);
        uint256 id = token.requestSeed();
        assertEq(id, 1);
        assertTrue(token.seedRequestIssued(id));
        assertEq(token.lastSeedRequestAt(), block.timestamp);
    }

    function test_RequestSeed_OnlyOnce() public {
        token.requestSeed();
        vm.expectRevert(CypherPunksToken.SeedAlreadyRequested.selector);
        token.requestSeed();
    }

    function test_RequestSeed_ExtraArgsMatchClientEncoding() public {
        uint256 id = token.requestSeed();
        // byte-exact VRFV2PlusClient._argsToBytes(ExtraArgsV1(false))
        assertEq(
            coordinator.extraArgsOf(id),
            abi.encodeWithSelector(bytes4(keccak256("VRF ExtraArgsV1")), false)
        );
    }

    // ------------------------------------------------------------ reRequest

    function test_ReRequest_RevertsBeforeTimeout() public {
        token.requestSeed();
        vm.warp(block.timestamp + 7 days - 1);
        vm.expectRevert(CypherPunksToken.ReRequestNotReady.selector);
        token.reRequest();
    }

    function testFuzz_ReRequest_AnyCallerAfterTimeout(address caller) public {
        vm.assume(caller != address(0));
        token.requestSeed();
        vm.warp(block.timestamp + 7 days);
        vm.prank(caller);
        uint256 id2 = token.reRequest();
        assertEq(id2, 2);
        assertTrue(token.seedRequestIssued(id2));
    }

    function test_ReRequest_RequiresPriorRequest() public {
        vm.expectRevert(CypherPunksToken.SeedNotRequested.selector);
        token.reRequest();
    }

    function test_ReRequest_DeadAfterFulfillment() public {
        uint256 id = token.requestSeed();
        coordinator.fulfill(id, 12345);
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        token.reRequest();
        // and the plain request path is equally dead
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        token.requestSeed();
    }

    // ---------------------------------------------------- I4 seed write-once

    function test_I4_DoubleFulfillmentReverts() public {
        uint256 id = token.requestSeed();
        coordinator.fulfill(id, 111);
        assertEq(token.seed(), 111);
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        coordinator.fulfill(id, 222);
        assertEq(token.seed(), 111, "seed moved");
    }

    /// M-01 (audit Rev 12): after a reRequest, ONLY the most recent request may
    /// fulfill the seed. A stale request delivered late — even if it arrives
    /// first — can no longer win: the operator re-requested precisely because
    /// they wanted a fresh word, so the fresh request is the one that seeds.
    function test_M01_OnlyMostRecentRequestCanFulfill() public {
        uint256 id1 = token.requestSeed();
        vm.warp(block.timestamp + 7 days);
        uint256 id2 = token.reRequest();
        assertEq(token.activeSeedRequestId(), id2, "reRequest supersedes the prior id");

        // the STALE request fulfilling first now REVERTS — it is no longer active
        vm.expectRevert(CypherPunksToken.UnknownRequest.selector);
        coordinator.fulfill(id1, 777);
        assertFalse(token.seedFulfilled(), "stale request must not seed");

        // only the active (most recent) request writes the seed
        coordinator.fulfill(id2, 888);
        assertEq(token.seed(), 888);

        // and the stale request stays dead after fulfillment (write-once)
        vm.expectRevert(CypherPunksToken.UnknownRequest.selector);
        coordinator.fulfill(id1, 777);
    }

    function test_I4_ZeroWordFulfillment_Regression() public {
        uint256 id = token.requestSeed();
        coordinator.fulfill(id, 0);
        assertTrue(token.seedFulfilled());
        assertEq(token.seed(), 0);
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        coordinator.fulfill(id, 999);
        // genesis fully operable on the zero word
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();
        assertTrue(token.genesisComplete());
    }

    function test_Fulfill_OnlyCoordinator() public {
        uint256 id = token.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.prank(makeAddr("impostor"));
        vm.expectRevert(CypherPunksToken.OnlyCoordinator.selector);
        token.rawFulfillRandomWords(id, words);
    }

    function test_Fulfill_UnknownRequestReverts() public {
        token.requestSeed();
        vm.expectRevert(CypherPunksToken.UnknownRequest.selector);
        coordinator.fulfillTo(address(token), 999, 1);
    }

    // ------------------------------------------------- lock ordering / I17

    /// Before fulfillment nothing readable reveals a seed and no genesis
    /// step runs; the rules were locked at deploy by construction.
    function test_LockOrdering_NothingBeforeFulfillment() public {
        assertEq(token.seed(), 0);
        assertFalse(token.seedFulfilled());
        vm.expectRevert(CypherPunksToken.SeedNotSet.selector);
        token.materializeBlob();
        vm.expectRevert(CypherPunksToken.BlobNotMaterialized.selector);
        token.mintArtistTail();
        vm.expectRevert(bytes('genesis incomplete'));
        ah.startAuctions();
    }

    /// Seed-ceremony rehearsal shape (doc §09): deploy → request → fulfill →
    /// four-step machine → auction #1 → first settlement. Real contracts,
    /// production seed path, arbitrary callers.
    function test_SeedCeremonyShape_EndToEnd() public {
        vm.prank(makeAddr("ceremonyCaller"));
        uint256 id = token.requestSeed();

        coordinator.fulfill(id, uint256(keccak256("mainnet rehearsal word")));
        assertTrue(token.seedFulfilled());

        vm.prank(makeAddr("step1"));
        token.materializeBlob();
        vm.prank(makeAddr("step2"));
        token.mintArtistTail();
        vm.prank(makeAddr("step3"));
        token.mintTeamTail();
        vm.prank(makeAddr("step4"));
        ah.startAuctions();

        assertEq(ah.auction().tokenId, 1);
        assertEq(token.balanceOf(artist), 100);
        assertEq(token.balanceOf(team), 100);

        // first day settles and chains
        address bidder = makeAddr("firstBidder");
        vm.deal(bidder, 1 ether);
        vm.prank(bidder);
        ah.createBid{value: 1 ether}(1);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(makeAddr("settler"));
        ah.settleCurrentAndCreateNewAuction();
        assertEq(token.ownerOf(1), bidder);
        assertEq(ah.auction().tokenId, 2);
        assertEq(address(splitter).balance, 1 ether);
    }
}
