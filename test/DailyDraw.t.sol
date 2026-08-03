// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DailyDraw} from "../src/lib/DailyDraw.sol";
import {ReservedDraw} from "../src/lib/ReservedDraw.sol";

/// Storage harness — the pool lives in contract storage exactly as it will
/// in the AuctionHouse/Token.
contract DailyDrawHarness {
    using DailyDraw for DailyDraw.Pool;

    DailyDraw.Pool internal pool;
    uint256 public nextAuctionId = 1;

    constructor(uint256 size) {
        pool.init(size);
    }

    function draw() external returns (uint256 index) {
        index = pool.drawNext(nextAuctionId);
        nextAuctionId++;
    }

    /// test-only: draw with an explicit auction id (entropy isolation tests)
    function drawWithId(uint256 id) external returns (uint256 index) {
        index = pool.drawNext(id);
    }

    function remaining() external view returns (uint256) {
        return pool.remaining;
    }
}

/// Property tests for doc §03 — library ancestors of invariants I1
/// (bijection across the full walk) and the O(1)-per-draw guarantee.
contract DailyDrawTest is Test {
    uint256 internal constant PUBLIC_COUNT = 9_800;
    uint256 internal constant DOMAIN = 10_000;

    DailyDrawHarness internal h;

    function setUp() public {
        h = new DailyDrawHarness(PUBLIC_COUNT);
    }

    // ---------------------------------------------------------------- I1 seed

    /// Full 9,800-draw walk: every pool index exactly once, then clean revert.
    function test_FullWalk_BijectionAndExhaustion() public {
        bool[] memory seen = new bool[](PUBLIC_COUNT);
        for (uint256 d = 0; d < PUBLIC_COUNT; d++) {
            // vary the entropy the way real settlements would
            vm.prevrandao(keccak256(abi.encode("settlement", d)));
            vm.roll(block.number + 1);
            uint256 idx = h.draw();
            assertLt(idx, PUBLIC_COUNT, "index out of pool");
            assertFalse(seen[idx], "duplicate draw");
            seen[idx] = true;
        }
        assertEq(h.remaining(), 0);
        // pool exhaustion: further draws revert cleanly
        vm.expectRevert(DailyDraw.PoolEmpty.selector);
        h.draw();
    }

    /// Composition with the reserved draw: reserved 200 + the 9,800 walk
    /// mapped through "i-th public piece" covers all 10,000 exactly once.
    function test_ComposedWithReservedDraw_CoversDomainOnce() public {
        uint256 seed = uint256(keccak256("genesis rehearsal"));
        (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(seed);

        bool[] memory reserved = new bool[](DOMAIN);
        bool[] memory assigned = new bool[](DOMAIN);
        for (uint256 i = 0; i < 100; i++) {
            reserved[artist[i]] = true;
            assigned[artist[i]] = true;
            reserved[team[i]] = true;
            assigned[team[i]] = true;
        }

        // publicPiece[i] = i-th design piece after removing the reserved 200
        uint16[] memory publicPiece = new uint16[](PUBLIC_COUNT);
        uint256 w = 0;
        for (uint256 piece = 0; piece < DOMAIN; piece++) {
            if (!reserved[piece]) publicPiece[w++] = uint16(piece);
        }
        assertEq(w, PUBLIC_COUNT);

        for (uint256 d = 0; d < PUBLIC_COUNT; d++) {
            vm.prevrandao(keccak256(abi.encode("day", d)));
            uint256 piece = publicPiece[h.draw()];
            assertFalse(assigned[piece], "piece assigned twice");
            assigned[piece] = true;
        }
        for (uint256 piece = 0; piece < DOMAIN; piece++) {
            assertTrue(assigned[piece], "gap in coverage");
        }
    }

    // ----------------------------------------------------------- O(1) storage

    /// Each draw touches a bounded, constant number of storage slots:
    /// reads ≤ 3 pool slots (remaining, slot i, slot n-1) and
    /// writes ≤ 3 (remaining, slot i, delete slot n-1) — independent of size.
    function test_ConstantStorageTouchesPerDraw() public {
        uint256 maxReads;
        uint256 maxWrites;
        for (uint256 d = 0; d < 50; d++) {
            vm.prevrandao(keccak256(abi.encode("gas", d)));
            vm.record();
            h.draw();
            (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(h));
            if (reads.length > maxReads) maxReads = reads.length;
            if (writes.length > maxWrites) maxWrites = writes.length;
        }
        emit log_named_uint("max storage accesses (reads incl. writes) per draw", maxReads);
        emit log_named_uint("max storage writes per draw", maxWrites);
        // Pool: <=3 reads + 3 writes; harness nextAuctionId adds 1+1.
        // vm.accesses lists writes in the reads array as well, so the read
        // bound covers reads + writes. The point is constancy w.r.t. pool
        // size (O(1) per doc SS03), not the exact figure.
        assertLe(maxReads, 10);
        assertLe(maxWrites, 5);
    }

    // ------------------------------------------------------------ entropy use

    /// prevrandao participates in the entropy: same pool state, different
    /// prevrandao, different draw (overwhelmingly).
    function test_PrevrandaoMatters() public {
        uint256 snap = vm.snapshotState();
        vm.prevrandao(bytes32(uint256(1)));
        uint256 a = h.draw();
        vm.revertToState(snap);
        vm.prevrandao(bytes32(uint256(2)));
        uint256 b = h.draw();
        // with 9,800 live slots a collision is ~1e-4; treat equality as failure
        assertTrue(a != b, "prevrandao ignored");
    }

    /// Entropy composition is exactly the doc's:
    /// keccak256(prevrandao, address(this), nextAuctionId, remaining).
    /// On a virgin pool the drawn index equals the raw entropy mod size.
    function test_EntropyCompositionMatchesDoc() public {
        DailyDrawHarness fresh = new DailyDrawHarness(PUBLIC_COUNT);
        vm.prevrandao(bytes32(uint256(9)));
        uint256 expected = uint256(
            keccak256(abi.encode(bytes32(uint256(9)), address(fresh), uint256(1), PUBLIC_COUNT))
        ) % PUBLIC_COUNT;
        assertEq(fresh.draw(), expected, "entropy composition drifted from doc SS03");
    }

    /// Auction id participates in the entropy: identical pool state and
    /// prevrandao, different id, different draw.
    function test_AuctionIdMatters() public {
        vm.prevrandao(bytes32(uint256(7)));
        uint256 snap = vm.snapshotState();
        uint256 a = h.drawWithId(1);
        vm.revertToState(snap);
        uint256 b = h.drawWithId(2);
        assertTrue(a != b, "auction id ignored in entropy");
    }

    /// Contract address participates: two identical fresh pools at the same
    /// prevrandao and id draw different indices.
    function test_ContractAddressMatters() public {
        DailyDrawHarness h4 = new DailyDrawHarness(PUBLIC_COUNT);
        DailyDrawHarness h5 = new DailyDrawHarness(PUBLIC_COUNT);
        vm.prevrandao(bytes32(uint256(11)));
        assertTrue(h4.draw() != h5.draw(), "contract address ignored in entropy");
    }
}
