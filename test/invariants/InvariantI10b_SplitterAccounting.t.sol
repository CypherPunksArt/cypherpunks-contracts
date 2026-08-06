// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CypherPunksSplitter} from "../../src/Splitter.sol";
import {SplitterHandler} from "./SplitterHandler.sol";

/// I10b (audit F3) — stateful fuzz of the Splitter's pull-payment accounting.
/// Across random fund / release / rotate / warp sequences:
///   • funds are conserved (held + released == received);
///   • total released never exceeds total received;
///   • no role is ever paid beyond its cumulative 90 / 5 / 5 entitlement.
/// Role-keyed counters mean this must hold even across payee rotations.
contract InvariantI10b_SplitterAccounting is Test {
    CypherPunksSplitter internal split;
    SplitterHandler internal handler;

    address payable internal company = payable(makeAddr("company"));
    address payable internal artist0 = payable(makeAddr("artist0"));
    address payable internal designer0 = payable(makeAddr("designer0"));
    address internal admin = makeAddr("payeeAdmin");

    // role ids are private in the contract; mirror them for the getter
    uint256 internal constant ROLE_COMPANY = 1;
    uint256 internal constant ROLE_ARTIST = 2;
    uint256 internal constant ROLE_DESIGNER = 3;

    function setUp() public {
        split = new CypherPunksSplitter(company, artist0, designer0, admin);
        handler = new SplitterHandler(split, company, artist0, designer0, admin);
        targetContract(address(handler));
    }

    /// Conservation: everything received is either still held or released out.
    function invariant_FundsConserved() public view {
        assertEq(
            address(split).balance + split.totalReleased(),
            handler.ghostReceived(),
            "conservation broken"
        );
        assertLe(split.totalReleased(), handler.ghostReceived(), "released exceeds received");
    }

    /// CP-LIVE-05: the run is only meaningful if the actions actually landed.
    /// Before this, artist/designer releases reverted in nearly every call and
    /// the suite still reported the coverage as exercised.
    function afterInvariant() public view {
        assertGt(handler.fundCount(), 0, "no funding landed");
        assertGt(handler.releaseCount(), 0, "no release landed");
        assertGt(handler.rotateCount(), 0, "no rotation matured");
    }

    /// No role is ever paid more than its cumulative 90 / 5 / 5 entitlement.
    function invariant_NoRoleOverpaid() public view {
        uint256 received = handler.ghostReceived();
        assertLe(split.releasedByRole(ROLE_COMPANY), (received * 90) / 100, "company overpaid");
        assertLe(split.releasedByRole(ROLE_ARTIST), (received * 5) / 100, "artist overpaid");
        assertLe(split.releasedByRole(ROLE_DESIGNER), (received * 5) / 100, "designer overpaid");
    }
}
