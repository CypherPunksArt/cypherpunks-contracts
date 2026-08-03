// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ReservedDraw} from "../../src/lib/ReservedDraw.sol";

/// I2 — Cornerstones public.
/// Design pieces 1 and 10,000 are never selected by the reserved draw, for
/// any seed. (Property test across random seeds.)
contract InvariantI2_CornerstonesPublic is Test {
    /// Fuzzed across seeds: neither cornerstone (piece index 0 or 9,999)
    /// appears in the artist or team reserved sets.
    function testFuzz_I2_CornerstonesNeverReserved(uint256 seed) public pure {
        (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(seed);
        for (uint256 i = 0; i < 100; i++) {
            assert(artist[i] != 0 && artist[i] != 9_999);
            assert(team[i] != 0 && team[i] != 9_999);
        }
    }

    /// Zero seed included explicitly (valid seed under the seedFulfilled
    /// guard) — cornerstones still excluded.
    function test_I2_ZeroSeed() public pure {
        (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(0);
        for (uint256 i = 0; i < 100; i++) {
            assert(artist[i] != 0 && artist[i] != 9_999);
            assert(team[i] != 0 && team[i] != 9_999);
        }
    }

    /// Exercises the cornerstone-skip branch: seeds whose raw draw would have
    /// selected a cornerstone still yield cornerstone-free reserved sets.
    function test_I2_SkipBranchStillExcludes() public view {
        uint256 hits;
        for (uint256 seed = 0; seed < 400 && hits < 3; seed++) {
            if (this.rawWouldSelectCornerstone(seed)) {
                (uint16[100] memory artist, uint16[100] memory team) = ReservedDraw.draw(seed);
                for (uint256 i = 0; i < 100; i++) {
                    assert(artist[i] != 0 && artist[i] != 9_999);
                    assert(team[i] != 0 && team[i] != 9_999);
                }
                hits++;
            }
        }
        assertEq(hits, 3, "expected skip-branch seeds within 400 candidates");
    }

    /// Reference re-simulation of the raw (non-skipping) partial Fisher-Yates.
    function rawWouldSelectCornerstone(uint256 seed) external pure returns (bool) {
        uint16[] memory arr = new uint16[](10_000);
        for (uint256 j = 0; j < 200; j++) {
            uint256 rand = uint256(keccak256(abi.encode(seed, j)));
            uint256 idx = j + (rand % (10_000 - j));
            uint256 picked = arr[idx] == 0 ? idx : arr[idx] - 1;
            arr[idx] = uint16((arr[j] == 0 ? j : arr[j] - 1) + 1);
            arr[j] = uint16(picked + 1);
            if (picked == 0 || picked == 9_999) return true;
        }
        return false;
    }
}
