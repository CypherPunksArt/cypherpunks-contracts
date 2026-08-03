// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IDescriptor} from "../../src/interfaces/IDescriptor.sol";

/// Test-only IDescriptor stand-in so DeployLib.validate (which now rejects a
/// zero descriptor) can be exercised in the deploy test and the seed-ceremony
/// rehearsal. The REAL Descriptor is Phase 8, blocked on doc §11 input 1;
/// this returns a trivial deterministic URI and must never reach mainnet.
contract DescriptorStub is IDescriptor {
    function tokenURI(uint256 tokenId, uint256 pieceId)
        external
        pure
        returns (string memory)
    {
        return string.concat("stub:", _u(tokenId), ":", _u(pieceId));
    }

    function _u(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 n = v;
        uint256 len;
        while (n != 0) {
            len++;
            n /= 10;
        }
        bytes memory b = new bytes(len);
        while (v != 0) {
            b[--len] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(b);
    }
}
