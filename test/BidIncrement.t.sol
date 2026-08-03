// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "./helpers/Fixture.sol";

/// Rev 2 outbid floor (doc §01/§06): required increase = max(2%, MIN_BID_STEP),
/// outbids only; opening bid needs only ≥ reserve (0 valid).
contract BidIncrementTest is Fixture {
    uint256 internal constant STEP = 0.001 ether;
    bytes internal constant INCREMENT_ERR =
        'Must send more than last bid by minBidIncrementPercentage amount';

    // -------------------------------------------------------------- opening

    function test_OpeningBid_ZeroWeiValid() public {
        uint256 tokenId = ah.auction().tokenId;
        address opener = makeAddr("opener");
        vm.prank(opener);
        ah.createBid{value: 0}(tokenId);
        assertEq(ah.auction().bidder, opener, "0-wei opening bid must stand");
        assertEq(ah.auction().amount, 0);
    }

    // ------------------------------------------------------------- boundary

    function test_Boundary_ExactStepSucceeds_OneWeiBelowReverts() public {
        // open at 0.01 ETH — dust region: 2% (0.0002) < MIN_BID_STEP (0.001)
        bidAs(makeAddr("opener"), 0.01 ether);
        uint256 tokenId = ah.auction().tokenId;

        // one wei below the floor: reverts, original require string
        address low = makeAddr("low");
        vm.deal(low, 1 ether);
        vm.prank(low);
        vm.expectRevert(INCREMENT_ERR);
        ah.createBid{value: 0.01 ether + STEP - 1}(tokenId);

        // exactly current + MIN_BID_STEP: succeeds
        address exact = makeAddr("exact");
        vm.deal(exact, 1 ether);
        vm.prank(exact);
        ah.createBid{value: 0.01 ether + STEP}(tokenId);
        assertEq(ah.auction().bidder, exact);
    }

    // ---------------------------------------------------------- dust region

    function test_Dust_ZeroWeiOutbidReverts() public {
        // 0-wei leader, 0-wei challenger — the old free-extension vector
        bidAs(makeAddr("leader"), 0);
        uint256 tokenId = ah.auction().tokenId;
        address challenger = makeAddr("challenger");
        vm.prank(challenger);
        vm.expectRevert(INCREMENT_ERR);
        ah.createBid{value: 0}(tokenId);
    }

    /// Equal-value outbids revert at ANY current bid level.
    function testFuzz_Dust_EqualValueOutbidReverts(uint256 current) public {
        current = bound(current, 0, 5 ether);
        bidAs(makeAddr("leader"), current);
        uint256 tokenId = ah.auction().tokenId;

        address challenger = makeAddr("challenger");
        vm.deal(challenger, current);
        vm.prank(challenger);
        vm.expectRevert(INCREMENT_ERR);
        ah.createBid{value: current}(tokenId);
        // and no anti-snipe extension happened via a failed bid
        assertEq(ah.auction().bidder, makeAddr("leader"));
    }

    /// Across the whole dust region the binding floor is exactly
    /// current + MIN_BID_STEP.
    function testFuzz_Dust_FloorIsStep(uint256 current) public {
        current = bound(current, 0, 0.05 ether - 1); // 2% < step everywhere here
        bidAs(makeAddr("leader"), current);
        uint256 tokenId = ah.auction().tokenId;

        address below = makeAddr("below");
        vm.deal(below, 1 ether);
        vm.prank(below);
        vm.expectRevert(INCREMENT_ERR);
        ah.createBid{value: current + STEP - 1}(tokenId);

        address atFloor = makeAddr("atFloor");
        vm.deal(atFloor, 1 ether);
        vm.prank(atFloor);
        ah.createBid{value: current + STEP}(tokenId);
        assertEq(ah.auction().bidder, atFloor);
    }

    // ------------------------------------------------------------ dominance

    /// Above the crossover (current ≥ 0.05 ETH) the 2% term governs and
    /// behaves exactly as pre-amendment.
    function testFuzz_Dominance_TwoPercentGoverns(uint256 current) public {
        current = bound(current, 0.05 ether, 100 ether);
        bidAs(makeAddr("leader"), current);
        uint256 tokenId = ah.auction().tokenId;

        uint256 pct = (current * 2) / 100; // >= STEP in this range
        assertGe(pct, STEP);

        address below = makeAddr("below");
        vm.deal(below, current + pct);
        vm.prank(below);
        vm.expectRevert(INCREMENT_ERR);
        ah.createBid{value: current + pct - 1}(tokenId);

        address atFloor = makeAddr("atFloor");
        vm.deal(atFloor, current + pct);
        vm.prank(atFloor);
        ah.createBid{value: current + pct}(tokenId);
        assertEq(ah.auction().bidder, atFloor);
    }

    /// Crossover point exactness: at 0.05 ETH both terms equal 0.001 ETH.
    function test_CrossoverPoint_TermsEqual() public {
        bidAs(makeAddr("leader"), 0.05 ether);
        uint256 tokenId = ah.auction().tokenId;
        assertEq((0.05 ether * 2) / 100, STEP);

        address exact = makeAddr("exact");
        vm.deal(exact, 1 ether);
        vm.prank(exact);
        ah.createBid{value: 0.05 ether + STEP}(tokenId);
        assertEq(ah.auction().bidder, exact);
    }
}
