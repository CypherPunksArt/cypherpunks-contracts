// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";
import {Handler} from "./Handler.sol";

/// I14 — Cadence immutability. No reachable state changes duration, buffer,
/// increment, reserve, supply, or splitter address. All are compile-time
/// constants or immutables; these invariants pin the getters across fuzzed
/// action sequences, and the setter-absence checks document the stripped
/// Nouns owner surface.
contract InvariantI14_CadenceImmutability is Fixture {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(ah, token, guardian);
        targetContract(address(handler));
    }

    function invariant_I14_ConstantsNeverMove() public view {
        assertEq(ah.DURATION(), 24 hours);
        assertEq(ah.TIME_BUFFER(), 10 minutes);
        assertEq(ah.MIN_BID_INCREMENT_PERCENTAGE(), 2);
        assertEq(ah.MIN_BID_STEP(), 0.001 ether);
        assertEq(ah.RESERVE_PRICE(), 0);
        assertEq(ah.UNPAUSE_DELAY(), 48 hours);
        assertEq(ah.splitter(), splitterAddr);
        assertEq(address(ah.token()), address(token));
        assertEq(ah.pauseGuardian(), guardian);
        assertEq(token.TOTAL_SUPPLY(), 10_000);
        assertEq(token.PUBLIC_COUNT(), 9_800);
        // VRF constants pinned (Phase 5 flag 3, doc §05 Rev 4)
        assertEq(token.RE_REQUEST_TIMEOUT(), 7 days);
        assertEq(token.VRF_CALLBACK_GAS_LIMIT(), 100_000);
        assertEq(token.VRF_REQUEST_CONFIRMATIONS(), 6);
    }

    /// The Nouns owner-setter selectors are gone from the bytecode: calling
    /// them hits no function and reverts without touching state.
    function test_I14_StrippedSettersDoNotExist() public {
        bytes4[4] memory strippedSelectors = [
            bytes4(keccak256("setTimeBuffer(uint56)")),
            bytes4(keccak256("setReservePrice(uint192)")),
            bytes4(keccak256("setMinBidIncrementPercentage(uint8)")),
            bytes4(keccak256("setPrices((uint32,uint64,address,uint96)[])"))
        ];
        for (uint256 i = 0; i < strippedSelectors.length; i++) {
            (bool ok,) = address(ah).call(abi.encodeWithSelector(strippedSelectors[i], 0));
            assertFalse(ok, "stripped setter selector answered");
        }
        assertEq(ah.TIME_BUFFER(), 10 minutes);
        assertEq(ah.RESERVE_PRICE(), 0);
    }
}
