// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";
import {Handler} from "./Handler.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";

/// I6 — One live auction. Exactly one auction active at all times between
/// genesis and final settlement (except while paused between auctions).
/// "At most one" is structural (a single storage slot); these invariants pin
/// the "exactly one" half: a settled slot without a successor exists only
/// while paused.
contract InvariantI6_OneLiveAuction is Fixture {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(ah, token, guardian);
        targetContract(address(handler));
    }

    function invariant_I6_OneLiveAuction() public view {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        // started at genesis step 4 and never unset
        assertTrue(a.startTime != 0, "no auction exists after start");
        // a settled auction with no successor is only reachable while paused
        // (walk completion is unreachable within invariant depth)
        if (a.settled) {
            assertTrue(ah.paused(), "settled auction without successor while unpaused");
        }
    }

    function invariant_I6_AuctionIdsAdvanceMonotonically() public view {
        // token ids equal auction sequence; the live auction is always the
        // latest drawn token
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        assertEq(uint256(a.tokenId), token.publicMinted(), "auction id != latest minted");
    }
}
