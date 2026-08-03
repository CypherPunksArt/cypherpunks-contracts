// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {SSTORE2} from "./lib/SSTORE2.sol";

/// @title The CypherPunks User Manual
///
/// The plain-text manual — how to bid, settle, and verify a CypherPunk — written
/// once to chain at construction and readable forever. No owner, no server, no
/// block explorer required: the instructions outlive the website. Immutable by
/// construction; the text can never be changed.
contract CypherPunksManual {
    /// @notice SSTORE2 data pointer holding the manual bytes.
    address public immutable pointer;

    /// @notice Byte length of the manual text.
    uint256 public immutable length;

    constructor(string memory text) {
        bytes memory data = bytes(text);
        require(data.length > 0, 'empty manual');
        length = data.length;
        pointer = SSTORE2.write(data);
    }

    /// @notice The full user manual as UTF-8 text.
    function read() external view returns (string memory) {
        return string(SSTORE2.read(pointer, 0, length));
    }
}
