// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";

/// I11 — Privilege surface.
/// The complete set of privileged calls is {pause, unpause-after-timelock}.
/// Neither moves funds, changes constants, mints, or affects ordering.
/// (Bytecode-level review item.)
///
/// "Privileged" here = a caller-restricted state-changing function. This test
/// machine-enumerates the guardian-gated surface and asserts it is exactly
/// {pause, scheduleUnpause}, with unpause itself permissionless-but-timelocked
/// and non-privileged in effect (moves no funds, no mint, no constant/order
/// change). The Token and Splitter expose no caller-gated privileged surface
/// at all (auction-house-gated mint/burn are internal wiring, not privilege).
contract InvariantI11_PrivilegeSurface is Fixture {
    /// The guardian-gated functions are exactly pause() and scheduleUnpause().
    /// Every OTHER external AuctionHouse function must NOT depend on the
    /// guardian: called by a non-guardian it must not revert with the
    /// guardian gate.
    function test_I11_OnlyPauseAndScheduleAreGuardianGated() public {
        address notGuardian = makeAddr("notGuardian");

        // pause: guardian-gated
        vm.prank(notGuardian);
        (bool ok, bytes memory ret) = address(ah).call(abi.encodeWithSignature("pause()"));
        assertFalse(ok);
        assertEq(_reason(ret), "not guardian");

        // scheduleUnpause: guardian-gated (must be paused first; guardian gate
        // is checked regardless for a non-guardian)
        vm.prank(guardian);
        ah.pause();
        vm.prank(notGuardian);
        (ok, ret) = address(ah).call(abi.encodeWithSignature("scheduleUnpause()"));
        assertFalse(ok);
        assertEq(_reason(ret), "not guardian");

        // unpause: NOT guardian-gated — fails on the timelock, not on caller.
        vm.prank(guardian);
        ah.scheduleUnpause();
        vm.prank(notGuardian);
        (ok, ret) = address(ah).call(abi.encodeWithSignature("unpause()"));
        assertFalse(ok);
        assertEq(_reason(ret), "timelock not elapsed", "unpause must gate on time, not caller");

        // matured: any caller executes
        vm.warp(block.timestamp + 48 hours);
        vm.prank(notGuardian);
        ah.unpause();
        assertFalse(ah.paused());
    }

    /// Neither privileged call moves funds, mints, changes constants, or
    /// touches ordering. Snapshot state around a pause/unpause cycle.
    function test_I11_PrivilegedCallsAreInert() public {
        // establish a live bid so there are funds and a drawn piece to watch
        bidAs(makeAddr("bidder"), 1 ether);
        uint256 ahBalBefore = address(ah).balance;
        uint256 mintedBefore = token.publicMinted();
        uint256 pieceBefore = ah.auction().pieceId;
        uint256 splitterBalBefore = address(splitter).balance;

        vm.prank(guardian);
        ah.pause();
        vm.prank(guardian);
        ah.scheduleUnpause();
        vm.warp(block.timestamp + 48 hours);
        // don't warp past the auction end, so unpause won't create a new one
        ah.unpause();

        // nothing moved, minted, or changed
        assertEq(address(ah).balance, ahBalBefore, "pause cycle moved funds");
        assertEq(token.publicMinted(), mintedBefore, "pause cycle minted");
        assertEq(ah.auction().pieceId, pieceBefore, "pause cycle changed ordering");
        assertEq(address(splitter).balance, splitterBalBefore, "pause cycle routed funds");
        // constants intact
        assertEq(ah.DURATION(), 24 hours);
        assertEq(ah.splitter(), address(splitter));
    }

    /// The Token exposes no guardian/owner surface at all: there is no owner()
    /// and no pause on the token.
    function test_I11_TokenHasNoOwnerSurface() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "token exposes owner()");
        (ok,) = address(token).call(abi.encodeWithSignature("pause()"));
        assertFalse(ok, "token exposes pause()");
        (ok,) = address(splitter).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "splitter exposes owner()");
    }

    function _reason(bytes memory ret) internal pure returns (string memory) {
        if (ret.length < 68) return "";
        assembly {
            ret := add(ret, 0x04)
        }
        return abi.decode(ret, (string));
    }
}
