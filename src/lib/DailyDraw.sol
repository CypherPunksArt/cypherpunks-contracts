// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title DailyDraw
/// @notice Settlement-time daily draw (doc §03): lazy Fisher–Yates without
///         replacement over a virtual pool, swap-and-pop, O(1) storage
///         touches per draw.
/// @dev The pool is over *public-pool indices* 0…size-1. The token contract
///      maps an index to its design piece (the i-th public piece after the
///      reserved 200 are removed, doc §03 sketch note). Values are stored
///      +1 so the mapping default (0) is the identity — zero initialization
///      cost, and the doc's zero-value sentinel issue is handled explicitly.
///
///      Reveal opacity (I15): entropy includes the settlement block's
///      prevrandao; this library exposes no view of a future draw and
///      drawNext is state-mutating by construction. This is a bound, not a
///      secrecy guarantee (audit M2 / residual R1): settlement is
///      permissionless with no deadline, and a block's prevrandao is public
///      the moment its parent lands — so whoever times the settlement call
///      can simulate drawNext against upcoming blocks and select *which*
///      piece appears *when*. Nothing mints cheap — every piece still clears
///      a public 24h auction — the residual is timing/selection only, and a
///      keeper settling promptly at endTime (see genesis runbook) collapses
///      the selection window to ~one block.
library DailyDraw {
    /// @dev Thrown when drawing from an exhausted pool (all 9,800 drawn).
    error PoolEmpty();

    struct Pool {
        /// @dev slot i holds (value+1); 0 means "value is i" (lazy identity)
        mapping(uint256 => uint256) slots;
        uint256 remaining;
    }

    /// @notice Arm the pool over indices 0…size-1.
    function init(Pool storage p, uint256 size) internal {
        p.remaining = size;
    }

    /// @notice Draw the next index without replacement. Entropy per doc §03:
    ///         keccak256(prevrandao, this, nextAuctionId, remaining).
    function drawNext(Pool storage p, uint256 nextAuctionId) internal returns (uint256 index) {
        uint256 n = p.remaining;
        if (n == 0) revert PoolEmpty();

        uint256 rand =
            uint256(keccak256(abi.encode(block.prevrandao, address(this), nextAuctionId, n)));
        uint256 i = rand % n;

        index = _val(p, i);
        unchecked {
            n--;
        }
        p.remaining = n;
        // swap-and-pop: last live slot's value moves into the drawn slot
        p.slots[i] = _val(p, n) + 1;
        delete p.slots[n];
    }

    function _val(Pool storage p, uint256 i) private view returns (uint256 v) {
        v = p.slots[i];
        return v == 0 ? i : v - 1;
    }
}
