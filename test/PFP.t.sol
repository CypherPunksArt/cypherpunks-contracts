// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WalkFixture} from "./helpers/WalkFixture.sol";
import {CypherPunksPFP, IPunkToken} from "../src/PFP.sol";

contract PFPTest is WalkFixture {
    CypherPunksPFP internal pfp;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        _deployAndOpen(uint256(keccak256("pfp seed")));
        pfp = new CypherPunksPFP(IPunkToken(address(token)));
    }

    function test_SetPfp_ByHolder() public {
        _settleDayWithBid(alice, 1 ether, "e1"); // alice owns #1
        vm.prank(alice);
        pfp.setPfp(1);
        assertEq(pfp.pfpRaw(alice), 1);
        assertEq(pfp.pfpOf(alice), 1);
    }

    function test_SetPfp_RevertsForNonHolder() public {
        _settleDayWithBid(alice, 1 ether, "e1");
        vm.prank(bob);
        vm.expectRevert(bytes("not the holder"));
        pfp.setPfp(1);
    }

    function test_PfpOf_ZeroAfterTransfer() public {
        _settleDayWithBid(alice, 1 ether, "e1");
        vm.prank(alice);
        pfp.setPfp(1);
        vm.prank(alice);
        token.transferFrom(alice, bob, 1); // alice sells #1
        assertEq(pfp.pfpRaw(alice), 1, "raw intent persists");
        assertEq(pfp.pfpOf(alice), 0, "verified read: 0 once sold");
        assertEq(pfp.pfpOf(bob), 0, "bob never set one");
    }

    function test_ClearPfp() public {
        _settleDayWithBid(alice, 1 ether, "e1");
        vm.prank(alice);
        pfp.setPfp(1);
        vm.prank(alice);
        pfp.clearPfp();
        assertEq(pfp.pfpRaw(alice), 0);
        assertEq(pfp.pfpOf(alice), 0);
    }

    function test_PfpOf_UnsetIsZero() public view {
        assertEq(pfp.pfpOf(bob), 0);
    }
}
