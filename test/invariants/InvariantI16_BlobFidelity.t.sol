// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenHarness} from "../helpers/TokenHarness.sol";
import {ReservedDraw} from "../../src/lib/ReservedDraw.sol";

/// I16 (Blob fidelity) — the publicPiece blob is byte-identical to an independent onchain
/// recomputation from the seed, and no submission path for an external
/// table exists (the blob address is set exactly once, only inside
/// materializeBlob, which takes no data parameters).
/// I16 — Blob fidelity.
/// The materialized publicPiece blob is byte-identical to an onchain
/// recomputation from the seed, and no code path accepts an externally
/// supplied table. (Fork test asserts equality; review confirms no
/// submission path.)
contract InvariantI16_BlobFidelity is Test {
    uint256 internal constant DOMAIN = 10_000;
    uint256 internal constant PUBLIC_COUNT = 9_800;

    TokenHarness internal token;

    function setUp() public {
        token = new TokenHarness(
            makeAddr("auctionHouse"),
            makeAddr("artistTreasury"),
            makeAddr("teamTreasury"),
            makeAddr("vrfCoordinator")
        );
    }

    /// Recompute the expected table independently (same published algorithm,
    /// separate code path in the test) and compare byte-for-byte against the
    /// deployed blob's code.
    function testFuzz_BlobMatchesIndependentRecomputation(uint256 seed) public {
        // zero is a valid seed under the seedFulfilled guard — no assume
        token.writeSeedForTest(seed);
        token.materializeBlob();

        // independent recomputation
        (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(seed);
        bool[] memory reserved = new bool[](DOMAIN);
        for (uint256 i = 0; i < 100; i++) {
            reserved[artist[i]] = true;
            reserved[team[i]] = true;
        }
        bytes memory expected = new bytes(PUBLIC_COUNT * 2);
        uint256 w = 0;
        for (uint256 piece = 0; piece < DOMAIN; piece++) {
            if (reserved[piece]) continue;
            expected[w] = bytes1(uint8(piece >> 8));
            expected[w + 1] = bytes1(uint8(piece));
            w += 2;
        }
        assertEq(w, PUBLIC_COUNT * 2);

        // raw code of the data contract: [STOP | table]
        address ptr = token.publicPieceBlob();
        bytes memory code = ptr.code;
        assertEq(code.length, PUBLIC_COUNT * 2 + 1, "blob size");
        assertEq(uint8(code[0]), 0, "missing STOP prefix");
        for (uint256 i = 0; i < 40; i++) {
            // spot-check via the public accessor across the table
            uint256 idx = (i * 251) % PUBLIC_COUNT;
            uint256 fromBlob = token.publicPieceAt(idx);
            uint256 fromExpected =
                (uint256(uint8(expected[idx * 2])) << 8) | uint256(uint8(expected[idx * 2 + 1]));
            assertEq(fromBlob, fromExpected, "accessor mismatch");
        }
        // full byte equality
        assertEq(keccak256(code), keccak256(abi.encodePacked(bytes1(0), expected)), "blob bytes");
    }

    /// The table is strictly increasing (a sorted complement of the reserved
    /// set) — a structural property of "i-th piece after removing reserved".
    function test_TableStrictlyIncreasing() public {
        token.writeSeedForTest(uint256(keccak256("mono")));
        token.materializeBlob();
        uint256 prev = token.publicPieceAt(0);
        for (uint256 i = 1; i < PUBLIC_COUNT; i++) {
            uint256 cur = token.publicPieceAt(i);
            assertGt(cur, prev, "table not strictly increasing");
            prev = cur;
        }
        // cornerstones are always public: piece 0 first, piece 9999 last
        assertEq(token.publicPieceAt(0), 0, "piece 1 (index 0) must be public");
        assertEq(token.publicPieceAt(PUBLIC_COUNT - 1), 9_999, "piece 10,000 must be public");
    }

    /// The blob pointer is write-once: after materialization the address
    /// never changes and re-materialization reverts (covered in the genesis
    /// suite; asserted here against the stored pointer for completeness).
    function test_BlobPointerStable() public {
        token.writeSeedForTest(42);
        token.materializeBlob();
        address ptr = token.publicPieceBlob();
        vm.expectRevert();
        token.materializeBlob();
        assertEq(token.publicPieceBlob(), ptr);
    }
}
