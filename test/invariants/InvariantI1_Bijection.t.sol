// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WalkFixture} from "../helpers/WalkFixture.sol";

/// I1 — Bijection.
/// Across the genesis reserved draw plus all 9,800 daily draws, every design
/// piece is assigned exactly once — no duplicates, no gaps. (Fork test:
/// full-walk enumeration.)
///
/// RUN TIER: WALK (slow). The full 9,800-settlement simulation. Ticks I5, I6,
/// I7 and I10 at every step per the doc §09 plan — one walk, five invariants.
/// The per-invariant files remain the fast suite; this is the CI/slow gate.
/// Run with:  forge test --match-contract InvariantI1_Bijection
contract InvariantI1_Bijection is WalkFixture {
    uint256 internal constant DOMAIN = 10_000;
    uint256 internal constant PUBLIC_COUNT = 9_800;

    function setUp() public {
        _deployAndOpen(uint256(keccak256("i1 full walk seed")));
    }

    /// forge-config: default.isolate = false
    function test_I1_FullWalk_AllPiecesOnce_TicksI5I6I7I10() public {
        bool[] memory assigned = new bool[](DOMAIN);

        // reserved 200 (genesis tails) assigned first
        for (uint256 id = 9_801; id <= 10_000; id++) {
            uint256 p = token.punkForToken(id);
            assertFalse(assigned[p], "I1: duplicate in reserved");
            assigned[p] = true;
            // reserved never holds a cornerstone (I2 corollary)
            assertTrue(p != 0 && p != 9_999, "cornerstone in reserved tail");
        }

        uint256 expectedSplitterBalance;

        // the public walk: 9,800 settlements
        for (uint256 day = 1; day <= PUBLIC_COUNT; day++) {
            // --- I6: exactly one live, unsettled auction with id == day ---
            assertEq(ah.auction().tokenId, day, "I6: auction id != day");
            assertFalse(ah.auction().settled, "I6: live auction already settled");

            uint256 piece = token.punkForToken(day);
            assertFalse(assigned[piece], "I1: duplicate across walk");
            assigned[piece] = true;

            // --- bid, then settle this day ---
            uint256 hammer = 0.001 ether + (day % 7) * 0.01 ether;
            address bidder = address(uint160(0x1000 + day));
            vm.deal(bidder, hammer);
            vm.prank(bidder);
            ah.createBid{value: hammer}(day);

            // --- I7: AH holds exactly the top bid pre-settlement ---
            assertEq(address(ah).balance, hammer, "I7: balance != top bid");

            vm.warp(uint256(ah.auction().endTime));
            vm.prevrandao(keccak256(abi.encode("randao", day)));
            ah.settleCurrentAndCreateNewAuction();

            // --- I5: minted strictly one, id advanced by one ---
            assertEq(token.publicMinted(), day == PUBLIC_COUNT ? day : day + 1, "I5: mint step");

            // --- I10: exact hammer routed to the splitter ---
            expectedSplitterBalance += hammer;
            assertEq(address(splitter).balance, expectedSplitterBalance, "I10: proceeds");

            // --- I7: AH drained to zero after settlement ---
            assertEq(address(ah).balance, 0, "I7: funds stranded after settle");
        }

        // --- I1: no gaps — all 10,000 pieces assigned exactly once ---
        for (uint256 p = 0; p < DOMAIN; p++) {
            assertTrue(assigned[p], "I1: gap in coverage");
        }

        // pool exhausted; the walk is complete
        assertEq(token.poolRemaining(), 0, "pool not exhausted");
        assertEq(token.publicMinted(), PUBLIC_COUNT, "not all public minted");
    }
}
