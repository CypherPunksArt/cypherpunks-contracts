// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ReservedDraw} from "../../src/lib/ReservedDraw.sol";

/// I3 — Reserved counts exact.
/// Artist set is exactly 100 and team set exactly 100; the sets never overlap.
contract InvariantI3_ReservedCountsExact is Test {
    uint256 internal constant DOMAIN = 10_000;

    /// Fuzzed across seeds: 100 + 100 distinct pieces, in-domain, disjoint.
    function testFuzz_I3_CountsExactAndDisjoint(uint256 seed) public pure {
        (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(seed);

        bool[] memory seen = new bool[](DOMAIN);
        uint256 artistCount;
        uint256 teamCount;
        for (uint256 i = 0; i < 100; i++) {
            assert(artist[i] < DOMAIN);
            assert(!seen[artist[i]]); // no dup within artist or vs team
            seen[artist[i]] = true;
            artistCount++;
        }
        for (uint256 i = 0; i < 100; i++) {
            assert(team[i] < DOMAIN);
            assert(!seen[team[i]]); // disjoint from artist and no dup within
            seen[team[i]] = true;
            teamCount++;
        }
        assert(artistCount == 100 && teamCount == 100);
    }

    function test_I3_ZeroSeed() public pure {
        (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(0);
        bool[] memory seen = new bool[](DOMAIN);
        for (uint256 i = 0; i < 100; i++) {
            assert(!seen[artist[i]]);
            seen[artist[i]] = true;
        }
        for (uint256 i = 0; i < 100; i++) {
            assert(!seen[team[i]]);
            seen[team[i]] = true;
        }
    }
}
