// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {SSTORE2} from "./lib/SSTORE2.sol";

/// @title The CypherPunks Auction Terminal
///
/// A complete, self-contained HTML interface to the daily auction, written
/// once to chain at construction and readable forever with a single eth_call.
/// The page needs only an RPC endpoint: it reads the live auction, renders
/// the punk through tokenURI, and shows the exact transaction fields to bid
/// or settle from any wallet. No owner, no server, no website: if everything
/// else disappears, the interface survives in the same place as the auction.
/// Immutable by construction; the page can never be changed.
contract AuctionTerminal {
    /// @notice SSTORE2 data pointer holding the page bytes.
    address public immutable pointer;

    /// @notice Byte length of the page.
    uint256 public immutable length;

    constructor(string memory html) {
        bytes memory data = bytes(html);
        require(data.length > 0, "empty ui");
        length = data.length;
        pointer = SSTORE2.write(data);
    }

    /// @notice The full auction terminal as a self-contained UTF-8 HTML document.
    function ui() external view returns (string memory) {
        return string(SSTORE2.read(pointer, 0, length));
    }
}
