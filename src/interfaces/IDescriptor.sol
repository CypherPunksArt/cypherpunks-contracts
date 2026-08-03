// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title IDescriptor
/// @notice Renderer interface (doc §02 row 3: Nouns Descriptor V2 pattern,
///         SSTORE2 + RLE, locked at deploy — no art governance).
/// @dev Implemented by src/Descriptor.sol (Phase 8, Rev 7 schema): fully
///      self-contained data-URI output, art pinned by page code hash.
///      I12 (render fidelity) runs against the real implementation.
interface IDescriptor {
    /// @notice Full data-URI token metadata for a token and its design piece.
    function tokenURI(uint256 tokenId, uint256 pieceId) external view returns (string memory);
}
