// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WalkFixture} from "../helpers/WalkFixture.sol";
import {CypherPunksToken} from "../../src/Token.sol";

/// I5 — Sequential mint.
/// Public token IDs mint strictly 1,2,3…9,800, one per settlement; total
/// minted ≤ 10,000; no mint function outside auction walk + genesis tail
/// batches.
contract InvariantI5_SequentialMint is WalkFixture {
    function setUp() public {
        _deployAndOpen(uint256(keccak256("i5 seed")));
    }

    /// Each settlement advances the public id by exactly one, in order.
    function test_I5_SequentialAcrossSettlements() public {
        assertEq(ah.auction().tokenId, 1);
        assertEq(token.publicMinted(), 1);
        for (uint256 day = 1; day <= 25; day++) {
            uint256 before = token.publicMinted();
            _settleDayWithBid(makeAddr("bidder"), 1 ether, keccak256(abi.encode(day)));
            assertEq(token.publicMinted(), before + 1, "id skipped or repeated");
            assertEq(ah.auction().tokenId, before + 1, "auction id not sequential");
        }
    }

    /// The only mint paths are the genesis tail batches and mintNext (auction
    /// house only). No public/general mint exists.
    function test_I5_NoMintOutsideWalkAndTails() public {
        // tails already minted in setUp: IDs 9,801–10,000 exist
        assertEq(token.ownerOf(9_801), artist);
        assertEq(token.ownerOf(10_000), team);

        // mintNext is auction-house-gated
        vm.expectRevert(CypherPunksToken.OnlyAuctionHouse.selector);
        token.mintNext(makeAddr("stranger"));

        // no other externally-callable mint selector answers
        bytes4[3] memory phantomMintSelectors = [
            bytes4(keccak256("mint(address)")),
            bytes4(keccak256("mint(address,uint256)")),
            bytes4(keccak256("safeMint(address,uint256)"))
        ];
        for (uint256 i = 0; i < 3; i++) {
            (bool ok,) = address(token).call(
                abi.encodeWithSelector(phantomMintSelectors[i], makeAddr("x"), uint256(1))
            );
            assertFalse(ok, "a public mint selector answered");
        }
    }

    /// Total minted never exceeds 10,000: the 200 tails plus at most 9,800
    /// public.
    function test_I5_TotalSupplyCeiling() public {
        // 200 tails minted; public capped by the pool
        assertLe(token.publicMinted() + 200, 10_000);
        // walk a few and re-check the ceiling holds
        for (uint256 day = 1; day <= 10; day++) {
            _settleDayWithBid(makeAddr("bidder"), 1 ether, keccak256(abi.encode("t", day)));
            assertLe(token.publicMinted() + 200, 10_000);
        }
    }
}
