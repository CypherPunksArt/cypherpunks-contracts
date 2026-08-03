// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @dev Matches the Nouns IWETH surface used by _safeTransferETHWithFallback.
interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function transfer(address to, uint256 value) external returns (bool);
}
