// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";

/// I13 — Anti-snipe correctness. Late bids extend exactly to now+buffer;
/// early bids never extend; extension requires a valid higher bid.
contract InvariantI13_AntiSnipe is Fixture {
    uint256 internal constant BUFFER = 10 minutes;

    function test_I13_EarlyBidNeverExtends() public {
        uint40 endBefore = ah.auction().endTime;
        // strictly outside the buffer window
        vm.warp(uint256(endBefore) - BUFFER - 1);
        bidAs(makeAddr("early"), 1 ether);
        assertEq(ah.auction().endTime, endBefore, "early bid extended");
    }

    function test_I13_BoundaryBidDoesNotExtend() public {
        uint40 endBefore = ah.auction().endTime;
        // exactly buffer remaining: endTime - now == BUFFER, strict `<` in
        // the verbatim Nouns condition means no extension
        vm.warp(uint256(endBefore) - BUFFER);
        bidAs(makeAddr("boundary"), 1 ether);
        assertEq(ah.auction().endTime, endBefore, "boundary bid extended");
    }

    function test_I13_LateBidExtendsExactlyToNowPlusBuffer() public {
        uint40 endBefore = ah.auction().endTime;
        vm.warp(uint256(endBefore) - 1);
        bidAs(makeAddr("sniper"), 1 ether);
        assertEq(ah.auction().endTime, uint40(block.timestamp + BUFFER), "wrong extension");
    }

    /// Fuzz over positions in the final window: extension is always exactly
    /// now+buffer, never more, never less.
    function testFuzz_I13_ExtensionExactness(uint256 offset) public {
        uint40 endBefore = ah.auction().endTime;
        offset = bound(offset, 1, BUFFER - 1); // strictly inside the window
        vm.warp(uint256(endBefore) - offset);
        bidAs(makeAddr("fuzzSniper"), 1 ether);
        assertEq(ah.auction().endTime, uint40(block.timestamp + BUFFER));
    }

    function test_I13_ExtensionRequiresValidHigherBid() public {
        uint40 endBefore = ah.auction().endTime;
        bidAs(makeAddr("leader"), 1 ether);
        vm.warp(uint256(endBefore) - 1);

        // too-low bid inside the window: reverts, no extension
        uint256 tokenId = ah.auction().tokenId;
        address low = makeAddr("low");
        vm.deal(low, 1 ether);
        vm.prank(low);
        vm.expectRevert(bytes('Must send more than last bid by minBidIncrementPercentage amount'));
        ah.createBid{value: 1 ether}(tokenId);
        assertEq(ah.auction().endTime, endBefore, "failed bid extended");

        // wrong token id inside the window: reverts, no extension
        vm.deal(low, 2 ether);
        vm.prank(low);
        vm.expectRevert(bytes('Punk not up for auction'));
        ah.createBid{value: 2 ether}(999);
        assertEq(ah.auction().endTime, endBefore, "wrong-id bid extended");
    }

    function test_I13_ExpiredBidReverts() public {
        uint256 tokenId = ah.auction().tokenId;
        warpPastEnd();
        address late = makeAddr("tooLate");
        vm.deal(late, 1 ether);
        vm.prank(late);
        vm.expectRevert(bytes('Auction expired'));
        ah.createBid{value: 1 ether}(tokenId);
    }
}
