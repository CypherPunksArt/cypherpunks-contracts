// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title The CypherPunks Mailing List
///
/// In the tradition of the 1992 original. Winning a CypherPunk earns its holder
/// one — and only one — entry on the mailing list: up to 256 bytes, written
/// straight to chain, kept forever. No owner, no admin, no edit or delete: once
/// an entry is sealed it is permanent, and the contract itself can never be
/// changed.
///
/// WHO MAY POST (holder model): whoever holds punk N while its posting window is
/// open. The right rides with the punk — one entry per punk — so a holder who
/// sells before writing passes the entry to the buyer. In practice the auction
/// winner receives the punk at settlement and writes immediately.
///
/// THE WINDOW is read live from the auction house, never stored here:
///   • Punk N (1 ≤ N < 9800): open exactly while auction N+1 is the live auction
///     — i.e. from N's settlement until N+1 settles.
///   • Punk 9800 (the last auctioned piece): opens at its settlement and never
///     closes — there is no auction 9801 to close it.
///   • The reserved tail (9801–10000) is never auctioned, so it can never post.
/// A punk that drew no bid is burned at settlement; `ownerOf` then reverts, so
/// it has no holder and cannot post (its window is irrelevant).
contract CypherPunksMailingList {
    /// @notice Maximum message size, in bytes (not characters — multibyte
    ///         glyphs cost more). A zero-length message is a deliberate blank seal.
    uint256 public constant MAX_BYTES = 256;

    /// @notice The CypherPunks token — source of truth for who holds a punk.
    CypherPunksTokenLike public immutable token;

    /// @notice The auction house — source of truth for the live posting window.
    CypherPunksAuctionHouseLike public immutable auctionHouse;

    /// @notice The last auctioned tokenId (Token.PUBLIC_COUNT, = 9800). Tokens
    ///         above this are the reserved tail and can never post.
    uint256 public immutable lastAuctionToken;

    struct Entry {
        address author; // who sealed the entry (holder at post time)
        uint40 timestamp; // block time of the seal; nonzero == sealed
        bytes message; // 0..256 bytes; zero-length is a blank seal
    }

    /// @dev tokenId => its single, permanent entry.
    mapping(uint256 => Entry) private _entries;

    /// @notice Total entries sealed (written or blank). One per punk, forever.
    uint256 public postCount;

    /// @notice Emitted once per punk when its entry is sealed. The public
    ///         archive is reconstructed from this log.
    event Posted(uint256 indexed tokenId, address indexed author, bytes message);

    constructor(CypherPunksTokenLike _token, CypherPunksAuctionHouseLike _auctionHouse) {
        require(address(_token) != address(0), 'token is zero');
        require(address(_auctionHouse) != address(0), 'auction house is zero');
        token = _token;
        auctionHouse = _auctionHouse;
        lastAuctionToken = _token.PUBLIC_COUNT();
    }

    // ------------------------------------------------------------------ write

    /// @notice Seal punk `tokenId`'s one mailing-list entry. Reverts unless the
    ///         caller holds the punk, its window is open, and it has not already
    ///         posted. `message` may be empty (a blank seal) or up to 256 bytes.
    function post(uint256 tokenId, bytes calldata message) external {
        require(message.length <= MAX_BYTES, 'message too long');
        require(!hasPosted(tokenId), 'already posted');
        require(windowOpen(tokenId), 'window closed');
        require(token.ownerOf(tokenId) == msg.sender, 'not the holder');

        _entries[tokenId] = Entry({author: msg.sender, timestamp: uint40(block.timestamp), message: message});
        unchecked {
            ++postCount;
        }
        emit Posted(tokenId, msg.sender, message);
    }

    // ------------------------------------------------------------------- read

    /// @notice Whether punk `tokenId`'s posting window is currently open.
    function windowOpen(uint256 tokenId) public view returns (bool) {
        if (tokenId == 0 || tokenId > lastAuctionToken) return false;
        CypherPunksAuctionHouseLike.Auction memory a = auctionHouse.auction();
        uint256 current = a.tokenId;
        bool settled = a.settled;
        if (tokenId == lastAuctionToken) {
            // The final piece: opens when it settles, never closes.
            return current == lastAuctionToken && settled;
        }
        // Every other piece: open exactly while auction N+1 is live.
        return current == tokenId + 1 && !settled;
    }

    /// @notice Whether punk `tokenId` has already sealed its entry.
    function hasPosted(uint256 tokenId) public view returns (bool) {
        return _entries[tokenId].timestamp != 0;
    }

    /// @notice Convenience gate for the UI: could `who` post for `tokenId` right
    ///         now? Never reverts (a burned/nonexistent punk returns false).
    function canPost(uint256 tokenId, address who) external view returns (bool) {
        if (who == address(0) || hasPosted(tokenId) || !windowOpen(tokenId)) return false;
        try token.ownerOf(tokenId) returns (address holder) {
            return holder == who;
        } catch {
            return false;
        }
    }

    /// @notice The sealed entry for `tokenId`. `timestamp == 0` means unsealed;
    ///         a nonzero timestamp with empty `message` is a blank seal.
    function entryOf(uint256 tokenId)
        external
        view
        returns (address author, uint40 timestamp, bytes memory message)
    {
        Entry storage e = _entries[tokenId];
        return (e.author, e.timestamp, e.message);
    }
}

/// @dev Minimal views this contract relies on from the CypherPunks token.
interface CypherPunksTokenLike {
    function ownerOf(uint256 tokenId) external view returns (address);
    function PUBLIC_COUNT() external view returns (uint256);
}

/// @dev Minimal view this contract relies on from the auction house. The tuple
///      order matches CypherPunksAuctionHouse.Auction exactly.
interface CypherPunksAuctionHouseLike {
    struct Auction {
        uint96 tokenId;
        uint16 pieceId;
        uint128 amount;
        uint40 startTime;
        uint40 endTime;
        address payable bidder;
        bool settled;
    }

    function auction() external view returns (Auction memory);
}
