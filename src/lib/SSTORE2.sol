// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title SSTORE2
/// @notice Minimal write-once data-contract storage (standard SSTORE2
///         pattern). Data is deployed as the runtime code of a fresh
///         contract, prefixed with a STOP byte so it can never execute.
/// @dev Used for the publicPiece table (doc §03/§04): ~19.6KB written once
///      during genesis, read with EXTCODECOPY thereafter.
library SSTORE2 {
    error WriteFailed();
    error ReadOutOfBounds();

    /// @dev Deploys [0x00 | data] as runtime code. Init code:
    ///      PUSH4 len; DUP1; PUSH1 0x0e; PUSH1 0; CODECOPY; PUSH1 0; RETURN
    function write(bytes memory data) internal returns (address ptr) {
        bytes memory initCode = abi.encodePacked(
            hex"63",
            uint32(data.length + 1),
            hex"80600e6000396000f3",
            hex"00",
            data
        );
        assembly {
            ptr := create(0, add(initCode, 0x20), mload(initCode))
        }
        if (ptr == address(0)) revert WriteFailed();
    }

    /// @notice Read data[start:start+len] (offsets exclude the STOP byte).
    function read(address ptr, uint256 start, uint256 len)
        internal
        view
        returns (bytes memory out)
    {
        uint256 size;
        assembly {
            size := extcodesize(ptr)
        }
        if (start + len + 1 > size) revert ReadOutOfBounds();
        out = new bytes(len);
        assembly {
            extcodecopy(ptr, add(out, 0x20), add(start, 1), len)
        }
    }

    /// @notice Big-endian uint16 at element index i (2 bytes per element).
    function readUint16(address ptr, uint256 i) internal view returns (uint256 v) {
        uint256 size;
        assembly {
            size := extcodesize(ptr)
        }
        uint256 offset = 1 + i * 2;
        if (offset + 2 > size) revert ReadOutOfBounds();
        assembly {
            let scratch := mload(0x40)
            mstore(scratch, 0)
            extcodecopy(ptr, scratch, offset, 2)
            v := shr(240, mload(scratch))
        }
    }
}
