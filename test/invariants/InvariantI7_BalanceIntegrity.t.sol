// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";
import {Handler} from "./Handler.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";

/// I7 — Balance integrity. AuctionHouse ETH balance == current top bid after
/// every state transition. No stranded funds, ever. The WETH fallback is what
/// keeps this exact even with hostile refund recipients.
contract InvariantI7_BalanceIntegrity is Fixture {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(ah, token, guardian);
        targetContract(address(handler));
    }

    function invariant_I7_BalanceEqualsTopBid() public view {
        CypherPunksAuctionHouse.Auction memory a = ah.auction();
        uint256 expected = a.settled ? 0 : uint256(a.amount);
        assertEq(address(ah).balance, expected, "AH balance != current top bid");
    }
}
