// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WalkFixture} from "./helpers/WalkFixture.sol";
import {CypherPunksMailingList, CypherPunksTokenLike, CypherPunksAuctionHouseLike} from "../src/MailingList.sol";

/// Mailing List — posting rights gated on hold-the-punk + live window, driven
/// through real auction settlements on the deployed contracts.
contract MailingListTest is WalkFixture {
    CypherPunksMailingList internal ml;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        _deployAndOpen(uint256(keccak256("mailing list seed")));
        ml = new CypherPunksMailingList(
            CypherPunksTokenLike(address(token)), CypherPunksAuctionHouseLike(address(ah))
        );
    }

    /// After winning #1, window opens while #2 is live; the holder can post once.
    function test_Post_WhenHolderAndWindowOpen() public {
        _settleDayWithBid(alice, 1 ether, "e1"); // alice wins #1, auction #2 live

        assertTrue(ml.windowOpen(1), "window 1 should be open");
        assertTrue(ml.canPost(1, alice), "alice can post 1");
        assertFalse(ml.canPost(1, bob), "bob cannot post 1");

        vm.prank(alice);
        ml.post(1, bytes("gm. the chain remembers."));

        (address author, uint40 ts, bytes memory msg_) = ml.entryOf(1);
        assertEq(author, alice);
        assertGt(ts, 0);
        assertEq(string(msg_), "gm. the chain remembers.");
        assertTrue(ml.hasPosted(1));
        assertEq(ml.postCount(), 1);
    }

    /// One entry per punk — a second post reverts.
    function test_Post_RevertsOnSecond() public {
        _settleDayWithBid(alice, 1 ether, "e1");
        vm.prank(alice);
        ml.post(1, bytes("first"));
        vm.prank(alice);
        vm.expectRevert(bytes("already posted"));
        ml.post(1, bytes("second"));
    }

    /// Can't post for a punk still up for auction (window not yet open).
    function test_Post_RevertsBeforeSettlement() public {
        _settleDayWithBid(alice, 1 ether, "e1"); // #2 is now the LIVE auction
        assertFalse(ml.windowOpen(2), "live auction has no open window");
        vm.prank(alice);
        vm.expectRevert(bytes("window closed"));
        ml.post(2, bytes("too early"));
    }

    /// A non-holder cannot post even inside the window.
    function test_Post_RevertsForNonHolder() public {
        _settleDayWithBid(alice, 1 ether, "e1"); // alice wins #1
        _settleDayWithBid(bob, 1 ether, "e2"); // bob wins #2, window 2 open
        assertTrue(ml.windowOpen(2));
        vm.prank(alice); // alice does not hold #2
        vm.expectRevert(bytes("not the holder"));
        ml.post(2, bytes("not mine"));
    }

    /// The window closes once the next auction settles.
    function test_Post_RevertsAfterWindowCloses() public {
        _settleDayWithBid(alice, 1 ether, "e1"); // alice wins #1
        _settleDayWithBid(bob, 1 ether, "e2"); // bob wins #2 (didn't post #1... alice's window still open here)
        _settleDayWithBid(carol, 1 ether, "e3"); // carol wins #3 -> window 2 now closed
        assertFalse(ml.windowOpen(2), "window 2 should be closed");
        vm.prank(bob);
        vm.expectRevert(bytes("window closed"));
        ml.post(2, bytes("too late"));
    }

    /// Over-long messages revert; a 256-byte message is accepted; empty is a blank seal.
    function test_Post_ByteLimitAndBlank() public {
        _settleDayWithBid(alice, 1 ether, "e1"); // alice wins #1, window open

        vm.prank(alice);
        vm.expectRevert(bytes("message too long"));
        ml.post(1, new bytes(257));

        vm.prank(alice);
        ml.post(1, new bytes(256)); // exactly at the limit
        (, uint40 ts, bytes memory m) = ml.entryOf(1);
        assertEq(m.length, 256);
        assertGt(ts, 0);
    }

    function test_Post_BlankSealIsSealed() public {
        _settleDayWithBid(alice, 1 ether, "e1");
        vm.prank(alice);
        ml.post(1, ""); // deliberate blank seal
        (address author, uint40 ts, bytes memory m) = ml.entryOf(1);
        assertEq(author, alice);
        assertGt(ts, 0);
        assertEq(m.length, 0);
        assertTrue(ml.hasPosted(1), "blank seal still counts as posted");
    }

    /// A burned (no-bid) punk has no holder and cannot post.
    function test_Post_BurnedPunkCannotPost() public {
        // settle #1 with NO bid -> it burns, #2 opens
        vm.warp(uint256(ah.auction().endTime));
        vm.prevrandao(bytes32("burn"));
        ah.settleCurrentAndCreateNewAuction();

        assertFalse(ml.canPost(1, alice), "burned punk: canPost false, never reverts");
        vm.prank(alice);
        vm.expectRevert(); // ownerOf reverts for a burned token
        ml.post(1, bytes("ghost"));
    }

    /// The reserved tail (9801–10000) is never auctioned and never posts.
    function test_ReservedTail_NeverPosts() public view {
        assertFalse(ml.windowOpen(9801));
        assertFalse(ml.windowOpen(10000));
        assertFalse(ml.windowOpen(0));
    }
}
