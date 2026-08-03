// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WalkFixture} from "../helpers/WalkFixture.sol";

/// I10 — Proceeds routing.
/// Every settlement transfers exactly the hammer price to the immutable
/// splitter; splitter shares never change.
contract InvariantI10_ProceedsRouting is WalkFixture {
    function setUp() public {
        _deployAndOpen(uint256(keccak256("i10 seed")));
    }

    /// Each settlement forwards exactly the winning bid to the splitter, and
    /// the splitter's 90/5/5 shares are constant throughout.
    function testFuzz_I10_ExactHammerToSplitter(uint256 a1, uint256 a2, uint256 a3) public {
        uint256[3] memory amounts = [
            bound(a1, 0.001 ether, 50 ether),
            bound(a2, 0.001 ether, 50 ether),
            bound(a3, 0.001 ether, 50 ether)
        ];

        uint256 cumulative;
        for (uint256 i = 0; i < 3; i++) {
            uint256 before = address(splitter).balance;
            uint256 hammer = _settleDayWithBid(makeAddr("bidder"), amounts[i], keccak256(abi.encode(i)));
            assertEq(address(splitter).balance - before, hammer, "splitter delta != hammer");
            cumulative += hammer;
            // shares never move
            assertEq(splitter.shares(companyPayee), 90);
            assertEq(splitter.shares(artistPayee), 5);
            assertEq(splitter.shares(designerPayee), 5);
        }
        assertEq(address(splitter).balance, cumulative, "cumulative proceeds mismatch");

        // and the split releases 90/5/5 exactly (company permissionless;
        // rotatable payees self-release per audit H-02)
        splitter.release(payable(companyPayee));
        vm.prank(artistPayee);
        splitter.release(payable(artistPayee));
        vm.prank(designerPayee);
        splitter.release(payable(designerPayee));
        assertEq(companyPayee.balance, (cumulative * 90) / 100);
        assertLe(
            cumulative - companyPayee.balance - artistPayee.balance - designerPayee.balance, 2
        ); // dust stays
    }

    /// No-bid day routes nothing (burn path) but still chains; splitter
    /// balance unchanged.
    function test_I10_NoBidRoutesNothing() public {
        uint256 before = address(splitter).balance;
        vm.warp(uint256(ah.auction().endTime));
        ah.settleCurrentAndCreateNewAuction();
        assertEq(address(splitter).balance, before, "no-bid day moved funds");
    }
}
