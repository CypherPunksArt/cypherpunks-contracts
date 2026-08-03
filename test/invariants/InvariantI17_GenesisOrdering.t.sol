// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenHarness} from "../helpers/TokenHarness.sol";
import {CypherPunksToken} from "../../src/Token.sol";

/// I17 (Genesis ordering) — genesis is a strictly ordered, permissionless, idempotent state
/// machine: seed → materializeBlob → mintArtistTail → mintTeamTail → auctions.
/// Out-of-order reverts; completed steps revert on re-call; auction minting
/// is unreachable until steps 1–3 complete.
/// I17 — Genesis ordering.
/// The genesis sequence (seed -> blob -> artist mint -> team mint ->
/// auction #1) executes only in order, each step exactly once, all steps
/// permissionless; auction #1 is unreachable until steps 1-3 complete.
contract InvariantI17_GenesisOrdering is Test {
    TokenHarness internal token;

    address internal auctionHouse = makeAddr("auctionHouse");
    address internal artist = makeAddr("artistTreasury");
    address internal team = makeAddr("teamTreasury");
    address internal splitter = makeAddr("splitter");

    uint256 internal constant SEED = uint256(keccak256("rehearsal seed"));

    function setUp() public {
        token = new TokenHarness(auctionHouse, artist, team, makeAddr("vrfCoordinator"));
    }

    // ------------------------------------------------------------- ordering

    function test_Ordering_BlobRequiresSeed() public {
        vm.expectRevert(CypherPunksToken.SeedNotSet.selector);
        token.materializeBlob();
    }

    function test_Ordering_ArtistRequiresBlob() public {
        token.writeSeedForTest(SEED);
        vm.expectRevert(CypherPunksToken.BlobNotMaterialized.selector);
        token.mintArtistTail();
    }

    function test_Ordering_TeamRequiresArtist() public {
        token.writeSeedForTest(SEED);
        token.materializeBlob();
        vm.expectRevert(CypherPunksToken.ArtistTailPending.selector);
        token.mintTeamTail();
    }

    function test_Ordering_AuctionGateUntilComplete() public {
        // stage 0: no seed
        vm.prank(auctionHouse);
        vm.expectRevert(CypherPunksToken.GenesisIncomplete.selector);
        token.mintNext(address(0xB0B));

        token.writeSeedForTest(SEED);
        vm.prank(auctionHouse);
        vm.expectRevert(CypherPunksToken.GenesisIncomplete.selector);
        token.mintNext(address(0xB0B));

        token.materializeBlob();
        vm.prank(auctionHouse);
        vm.expectRevert(CypherPunksToken.GenesisIncomplete.selector);
        token.mintNext(address(0xB0B));

        token.mintArtistTail();
        vm.prank(auctionHouse);
        vm.expectRevert(CypherPunksToken.GenesisIncomplete.selector);
        token.mintNext(address(0xB0B));

        token.mintTeamTail();
        assertTrue(token.genesisComplete());
        vm.prank(auctionHouse);
        uint256 id = token.mintNext(address(0xB0B));
        assertEq(id, 1);
    }

    // ----------------------------------------------------------- idempotency

    function test_Idempotency_EveryStepRevertsOnRecall() public {
        token.writeSeedForTest(SEED);
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        token.writeSeedForTest(SEED);

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

    /// Seed write-once holds for ANY first word, including zero — the
    /// seedFulfilled flag guards the write, not the seed value (doc §05
    /// amendment).
    function testFuzz_SeedWriteOnce(uint256 first, uint256 second) public {
        token.writeSeedForTest(first);
        assertTrue(token.seedFulfilled());
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        token.writeSeedForTest(second);
        assertEq(token.seed(), first);
    }

    /// The zero VRF word explicitly: seed stays 0, yet the write is closed
    /// and genesis proceeds normally.
    function test_SeedWriteOnce_ZeroWord() public {
        token.writeSeedForTest(0);
        assertEq(token.seed(), 0);
        assertTrue(token.seedFulfilled());
        vm.expectRevert(CypherPunksToken.SeedAlreadySet.selector);
        token.writeSeedForTest(1);
        // genesis is fully operable on a zero seed
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();
        assertTrue(token.genesisComplete());
    }

    // -------------------------------------------------------- permissionless

    /// Any caller can run every genesis step (steps are permissionless).
    function testFuzz_PermissionlessCallers(address c1, address c2, address c3) public {
        vm.assume(c1 != address(0) && c2 != address(0) && c3 != address(0));
        token.writeSeedForTest(SEED);
        vm.prank(c1);
        token.materializeBlob();
        vm.prank(c2);
        token.mintArtistTail();
        vm.prank(c3);
        token.mintTeamTail();
        assertTrue(token.genesisComplete());
    }

    // ------------------------------------------------------------ end state

    function test_TailMintsLandExactly() public {
        token.writeSeedForTest(SEED);
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();

        assertEq(token.balanceOf(artist), 100);
        assertEq(token.balanceOf(team), 100);
        for (uint256 id = 9_801; id <= 9_900; id++) {
            assertEq(token.ownerOf(id), artist);
        }
        for (uint256 id = 9_901; id <= 10_000; id++) {
            assertEq(token.ownerOf(id), team);
        }
        // no public token exists yet
        assertEq(token.publicMinted(), 0);
        vm.expectRevert();
        token.ownerOf(1);
    }
}
