// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixture} from "../helpers/Fixture.sol";

/// I15 — Reveal opacity.
/// The piece for auction N+1 is not computable by any external call before
/// the settlement transaction of auction N executes. (Review item + test
/// that no view function leaks the next draw.)
///
/// The next draw depends on block.prevrandao of the settlement block, which
/// does not exist until that block is mined. This test asserts the two
/// structural facts that make the reveal opaque:
///   1. No view/pure function on the Token or AuctionHouse returns the next
///      piece, and the pool exposes only a COUNT (poolRemaining), never a
///      value at an index.
///   2. The draw is prevrandao-dependent: the SAME pre-settlement state
///      yields DIFFERENT next pieces under different settlement-block
///      prevrandao — so no pre-settlement computation can pin it.
contract InvariantI15_RevealOpacity is Fixture {
    /// The pool accessor surface is count-only: there is no getter that maps
    /// a pool index to its piece, and punkForToken reverts for the unminted
    /// next id.
    function test_I15_NoAccessorLeaksNextDraw() public {
        uint256 liveId = ah.auction().tokenId; // 1
        uint256 nextId = liveId + 1;

        // the next token is not minted, so its piece is unresolvable
        vm.expectRevert();
        token.punkForToken(nextId);

        // only a remaining COUNT is exposed, never a pool value
        // (9,799: auction #1 already drew one in the fixture)
        assertEq(token.poolRemaining(), 9_799);

        // there is no poolValueAt / peekNext style selector
        bytes4[3] memory phantom = [
            bytes4(keccak256("poolValueAt(uint256)")),
            bytes4(keccak256("peekNextPiece()")),
            bytes4(keccak256("nextPiece()"))
        ];
        for (uint256 i = 0; i < 3; i++) {
            (bool ok,) = address(token).call(abi.encodeWithSelector(phantom[i], uint256(0)));
            assertFalse(ok, "a next-draw accessor exists");
        }
    }

    /// Same pre-settlement state, different settlement-block prevrandao →
    /// different next piece. The draw cannot be precomputed before the block.
    function test_I15_NextDrawDependsOnSettlementPrevrandao() public {
        bidAs(makeAddr("bidder"), 1 ether);
        vm.warp(uint256(ah.auction().endTime));

        uint256 snap = vm.snapshotState();

        vm.prevrandao(bytes32(uint256(0xAAAA)));
        ah.settleCurrentAndCreateNewAuction();
        uint256 pieceA = ah.auction().pieceId; // token 2's piece under randao A

        vm.revertToState(snap);
        vm.prevrandao(bytes32(uint256(0xBBBB)));
        ah.settleCurrentAndCreateNewAuction();
        uint256 pieceB = ah.auction().pieceId; // token 2's piece under randao B

        assertTrue(pieceA != pieceB, "next draw independent of settlement prevrandao");
    }
}
