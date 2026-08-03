// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";

/// Adversarial bidder bots (doc §09). Each attacks the refund path or the
/// cadence; the suites assert I8/I9/I13 hold against all of them.

/// Reverts on any ETH receive — tries to brick outbids/refunds.
contract RevertOnReceiveBidder {
    CypherPunksAuctionHouse internal ah;

    constructor(CypherPunksAuctionHouse _ah) {
        ah = _ah;
    }

    function bid(uint256 tokenId, uint256 value) external {
        ah.createBid{value: value}(tokenId);
    }

    receive() external payable {
        revert("no ETH accepted");
    }
}

/// Returns a huge returndata blob on receive — tries to gas-grief the
/// outbidder through returndata copying. The verbatim assembly call copies
/// zero returndata, so the bomb is never read.
contract ReturnBombBidder {
    CypherPunksAuctionHouse internal ah;

    constructor(CypherPunksAuctionHouse _ah) {
        ah = _ah;
    }

    function bid(uint256 tokenId, uint256 value) external {
        ah.createBid{value: value}(tokenId);
    }

    fallback() external payable {
        assembly {
            return(0, 0x100000) // 1 MiB of zeroes
        }
    }

    receive() external payable {
        assembly {
            return(0, 0x100000)
        }
    }
}

/// Burns all forwarded gas on receive — the 30k stipend caps the damage.
contract GasGrieferBidder {
    CypherPunksAuctionHouse internal ah;

    constructor(CypherPunksAuctionHouse _ah) {
        ah = _ah;
    }

    function bid(uint256 tokenId, uint256 value) external {
        ah.createBid{value: value}(tokenId);
    }

    receive() external payable {
        uint256 x;
        while (true) {
            unchecked {
                x++;
            }
            assembly {
                sstore(x, x)
            }
        }
    }
}

/// Attempts reentry into bid and settle from inside the refund. The 30k
/// stipend cannot fund a state-changing reentry; flags record any success.
contract ReentrancyProber {
    CypherPunksAuctionHouse internal ah;
    bool public reenteredBid;
    bool public reenteredSettle;

    constructor(CypherPunksAuctionHouse _ah) {
        ah = _ah;
    }

    function bid(uint256 tokenId, uint256 value) external {
        ah.createBid{value: value}(tokenId);
    }

    receive() external payable {
        uint96 tokenId = 0;
        (tokenId,,,,,,) = ah.auctionStorage();
        try ah.createBid{value: 0}(tokenId) {
            reenteredBid = true;
        } catch {}
        try ah.settleCurrentAndCreateNewAuction() {
            reenteredSettle = true;
        } catch {}
    }
}
