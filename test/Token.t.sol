// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenHarness} from "./helpers/TokenHarness.sol";
import {CypherPunksToken} from "../src/Token.sol";
import {DailyDraw} from "../src/lib/DailyDraw.sol";

/// Token surface and mint mechanics: standards-clean ERC-721 (zero secondary
/// royalties per Rev 3 — no ERC-2981), strictly sequential public mints (I5
/// seed), piece assignment via blob + daily draw, and the full-walk coverage
/// test (I1 at token level).
contract TokenTest is Test {
    uint256 internal constant PUBLIC_COUNT = 9_800;
    uint256 internal constant DOMAIN = 10_000;

    TokenHarness internal token;

    address internal auctionHouse = makeAddr("auctionHouse");
    address internal artist = makeAddr("artistTreasury");
    address internal team = makeAddr("teamTreasury");
    address internal winner = makeAddr("winner");

    function setUp() public {
        token = new TokenHarness(auctionHouse, artist, team, makeAddr("vrfCoordinator"));
        token.writeSeedForTest(uint256(keccak256("token suite seed")));
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();
    }

    // ------------------------------------------------------------ 721 surface

    /// Interface-surface pin (Rev 3 ruling): exactly ERC-165 + ERC-721 +
    /// ERC-721Metadata are supported; ERC-2981 is explicitly NOT — zero
    /// secondary royalties, CryptoPunks/Nouns posture.
    function test_InterfaceSurfacePinned() public view {
        assertEq(token.name(), "CypherPunks");
        assertEq(token.symbol(), "PUNK");
        assertTrue(token.supportsInterface(0x01ffc9a7), "ERC165 must be supported");
        assertTrue(token.supportsInterface(0x80ac58cd), "ERC721 must be supported");
        assertTrue(token.supportsInterface(0x5b5e139f), "ERC721Metadata must be supported");
        assertFalse(token.supportsInterface(0x2a55205a), "ERC2981 must NOT be supported");
        assertFalse(token.supportsInterface(0x780e9d63), "ERC721Enumerable not implemented");
        assertFalse(token.supportsInterface(0xffffffff), "ERC165 sanity");
    }

    /// INV-G3 access: only the AuctionHouse may burn, and the piece
    /// assignment survives the burn (audit port, test-out).
    function test_Burn_OnlyAuctionHouse() public {
        vm.prank(auctionHouse);
        uint256 id = token.mintNext(auctionHouse);
        uint256 piece = token.punkForToken(id);

        vm.expectRevert(CypherPunksToken.OnlyAuctionHouse.selector);
        token.burn(id);
        vm.prank(makeAddr("mallory"));
        vm.expectRevert(CypherPunksToken.OnlyAuctionHouse.selector);
        token.burn(id);

        vm.prank(auctionHouse);
        token.burn(id);

        vm.expectRevert();
        token.ownerOf(id);
        assertEq(token.punkForToken(id), piece, "piece survives burn");
    }

    // ------------------------------------------------------------ mint gating

    function test_MintNext_OnlyAuctionHouse() public {
        vm.expectRevert(CypherPunksToken.OnlyAuctionHouse.selector);
        token.mintNext(winner);
        vm.prank(makeAddr("mallory"));
        vm.expectRevert(CypherPunksToken.OnlyAuctionHouse.selector);
        token.mintNext(winner);
    }

    function test_MintNext_SequentialIdsAndAssignment() public {
        for (uint256 expected = 1; expected <= 5; expected++) {
            vm.prevrandao(keccak256(abi.encode("blk", expected)));
            vm.prank(auctionHouse);
            uint256 id = token.mintNext(winner);
            assertEq(id, expected, "I5: strictly sequential");
            assertEq(token.ownerOf(id), auctionHouse == winner ? auctionHouse : winner);
            // assigned piece is a public piece and consistent with the blob
            uint256 piece = token.punkForToken(id);
            assertLt(piece, DOMAIN);
        }
        assertEq(token.publicMinted(), 5);
        assertEq(token.poolRemaining(), PUBLIC_COUNT - 5);
    }

    function test_PunkForToken_RevertsForUnminted() public {
        vm.expectRevert(CypherPunksToken.NonexistentToken.selector);
        token.punkForToken(1);
        vm.expectRevert(CypherPunksToken.NonexistentToken.selector);
        token.punkForToken(10_001);
    }

    function test_TailPiecesExposedViaPunkForToken() public view {
        // tails were minted in setUp; every tail token resolves to a piece
        for (uint256 id = 9_801; id <= 10_000; id += 37) {
            uint256 piece = token.punkForToken(id);
            assertLt(piece, DOMAIN);
            assertTrue(piece != 0 && piece != 9_999, "cornerstone in a tail");
        }
    }

    function test_TokenURIPlaceholderCarriesPiece() public {
        vm.prank(auctionHouse);
        uint256 id = token.mintNext(winner);
        string memory uri = token.tokenURI(id);
        assertTrue(bytes(uri).length > 0);
        // placeholder is a data URI until the Descriptor lands (doc SS11)
        assertEq(_slice(uri, 0, 22), "data:application/json;");
    }

    // ---------------------------------------------------------- full walk I1

    /// Mint all 9,800: strictly sequential IDs, every design piece assigned
    /// exactly once across tails + walk, pool exhausts cleanly.
    function test_FullWalk_AllPiecesAssignedOnce() public {
        bool[] memory assigned = new bool[](DOMAIN);
        // tails first (minted in setUp)
        for (uint256 id = 9_801; id <= 10_000; id++) {
            uint256 p = token.punkForToken(id);
            assertFalse(assigned[p]);
            assigned[p] = true;
        }
        for (uint256 d = 1; d <= PUBLIC_COUNT; d++) {
            vm.prevrandao(keccak256(abi.encode("walk", d)));
            vm.prank(auctionHouse);
            uint256 id = token.mintNext(winner);
            assertEq(id, d);
            uint256 p = token.punkForToken(id);
            assertFalse(assigned[p], "piece assigned twice");
            assigned[p] = true;
        }
        for (uint256 p = 0; p < DOMAIN; p++) {
            assertTrue(assigned[p], "gap in assignment");
        }
        assertEq(token.poolRemaining(), 0);
        // exhaustion: next mint reverts cleanly
        vm.prank(auctionHouse);
        vm.expectRevert(DailyDraw.PoolEmpty.selector);
        token.mintNext(winner);
    }

    // --------------------------------------------------------------- helpers

    function _slice(string memory s, uint256 start, uint256 len)
        internal
        pure
        returns (string memory)
    {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = b[start + i];
        }
        return string(out);
    }
}
