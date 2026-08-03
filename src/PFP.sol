// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title CypherPunks PFP registry
///
/// Immutable, no-owner. Any punk holder may set that punk as their profile
/// picture; anyone can read it back. `setPfp` records intent only — because
/// punks trade, display surfaces should prefer `pfpOf`, which returns the punk
/// only while the account still holds it (else zero).
contract CypherPunksPFP {
    /// @notice The CypherPunks token — source of truth for ownership.
    IPunkToken public immutable token;

    /// @dev account => chosen tokenId (0 = unset).
    mapping(address => uint256) private _pfp;

    event PfpSet(address indexed account, uint256 indexed tokenId);
    event PfpCleared(address indexed account);

    constructor(IPunkToken _token) {
        require(address(_token) != address(0), 'token is zero');
        token = _token;
    }

    /// @notice Set `tokenId` as the caller's PFP. Caller must currently hold it.
    function setPfp(uint256 tokenId) external {
        require(token.ownerOf(tokenId) == msg.sender, 'not the holder');
        _pfp[msg.sender] = tokenId;
        emit PfpSet(msg.sender, tokenId);
    }

    /// @notice Clear the caller's PFP.
    function clearPfp() external {
        delete _pfp[msg.sender];
        emit PfpCleared(msg.sender);
    }

    /// @notice The raw tokenId an account set (0 if none). Does NOT re-check
    ///         current ownership.
    function pfpRaw(address account) external view returns (uint256) {
        return _pfp[account];
    }

    /// @notice The account's PFP, verified: the tokenId only if the account
    ///         still holds it; otherwise 0 (sold, transferred, or burned).
    function pfpOf(address account) external view returns (uint256) {
        uint256 id = _pfp[account];
        if (id == 0) return 0;
        try token.ownerOf(id) returns (address holder) {
            return holder == account ? id : 0;
        } catch {
            return 0;
        }
    }
}

/// @dev Minimal ownership view from the CypherPunks token.
interface IPunkToken {
    function ownerOf(uint256 tokenId) external view returns (address);
}
