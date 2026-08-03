// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title ReservedDraw
/// @notice Genesis reserved-200 draw. The single VRF seed's only job (doc §04):
///         a seeded Fisher–Yates over the full 10,000, taking the first 200
///         non-cornerstone outputs — first 100 artist, next 100 team.
/// @dev Pure function of the seed; runs once at fulfillment. Design pieces
///      1 and 10,000 (indices 0 and 9,999) are skipped if selected and the
///      draw continues — deterministic, no human hand. Publishing the seed
///      verifies this draw and leaks nothing about the daily order (§05).
library ReservedDraw {
    uint256 internal constant DOMAIN = 10_000;
    uint256 internal constant ARTIST_COUNT = 100;
    uint256 internal constant TEAM_COUNT = 100;
    uint256 internal constant RESERVED_COUNT = ARTIST_COUNT + TEAM_COUNT;
    /// @dev Design pieces 1 and 10,000 as zero-based indices.
    uint256 internal constant CORNERSTONE_A = 0;
    uint256 internal constant CORNERSTONE_B = 9_999;

    /// @notice Draw the reserved sets for a seed.
    /// @return artist The 100 artist pieces, in draw order.
    /// @return team The 100 team pieces, in draw order.
    function draw(uint256 seed)
        internal
        pure
        returns (uint16[ARTIST_COUNT] memory artist, uint16[TEAM_COUNT] memory team)
    {
        // Virtual array arr[i] = i, stored +1 so the memory default (0) means
        // "identity". Only the prefix touched by the partial shuffle is ever
        // written.
        uint16[] memory arr = new uint16[](DOMAIN);

        uint256 collected = 0;
        uint256 j = 0;
        while (collected < RESERVED_COUNT) {
            // step entropy: seed and step index only — fully reproducible
            uint256 rand = uint256(keccak256(abi.encode(seed, j)));
            uint256 idx = j + (rand % (DOMAIN - j));

            uint256 picked = _val(arr, idx);
            // swap-and-advance (Fisher–Yates step)
            arr[idx] = uint16(_val(arr, j) + 1);
            arr[j] = uint16(picked + 1);
            j++;

            if (picked == CORNERSTONE_A || picked == CORNERSTONE_B) {
                // cornerstone selected: skip, draw continues to next output
                continue;
            }
            if (collected < ARTIST_COUNT) {
                artist[collected] = uint16(picked);
            } else {
                team[collected - ARTIST_COUNT] = uint16(picked);
            }
            collected++;
        }
    }

    function _val(uint16[] memory arr, uint256 i) private pure returns (uint256) {
        uint256 v = arr[i];
        return v == 0 ? i : v - 1;
    }
}
