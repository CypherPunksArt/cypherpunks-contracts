// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ReservedDraw} from "../src/lib/ReservedDraw.sol";

/// Library mechanics for doc §04's reserved draw. The I2 (cornerstones
/// never selected) and I3 (counts exact / disjoint) PROPERTIES live in the
/// numbered files test/invariants/InvariantI2_*.t.sol and InvariantI3_*.t.sol;
/// this file covers determinism and seed-sensitivity only, to avoid
/// duplicating the invariant assertions.
contract ReservedDrawTest is Test {
    uint256 internal constant DOMAIN = 10_000;

    /// Deterministic: same seed, same sets, same order.
    function testFuzz_Deterministic(uint256 seed) public pure {
        (uint16[100] memory a1, uint16[100] memory t1) = ReservedDraw.draw(seed);
        (uint16[100] memory a2, uint16[100] memory t2) = ReservedDraw.draw(seed);
        for (uint256 i = 0; i < 100; i++) {
            assert(a1[i] == a2[i]);
            assert(t1[i] == t2[i]);
        }
    }

    /// Different seeds should (overwhelmingly) give different draws — guards
    /// against the seed being ignored by accident.
    function testFuzz_SeedActuallyUsed(uint256 seedA, uint256 seedB) public pure {
        vm.assume(seedA != seedB);
        (uint16[100] memory a1,) = ReservedDraw.draw(seedA);
        (uint16[100] memory a2,) = ReservedDraw.draw(seedB);
        bool anyDiff;
        for (uint256 i = 0; i < 100; i++) {
            if (a1[i] != a2[i]) {
                anyDiff = true;
                break;
            }
        }
        assert(anyDiff);
    }

}
