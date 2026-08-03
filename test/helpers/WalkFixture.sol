// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CypherPunksToken} from "../../src/Token.sol";
import {CypherPunksAuctionHouse} from "../../src/AuctionHouse.sol";
import {CypherPunksSplitter} from "../../src/Splitter.sol";
import {IDescriptor} from "../../src/interfaces/IDescriptor.sol";
import {VRFCoordinatorV2PlusMock} from "./VRFCoordinatorV2PlusMock.sol";
import {WETHMock} from "./Fixture.sol";

/// Full production deployment through the real VRF seed path and genesis
/// state machine — no TokenHarness. Used by the walk (I1) and the
/// auction-level invariants that need genuine settlement mechanics.
abstract contract WalkFixture is Test {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    VRFCoordinatorV2PlusMock internal coord;
    CypherPunksToken internal token;
    CypherPunksAuctionHouse internal ah;
    CypherPunksSplitter internal splitter;

    address internal artist = makeAddr("artistTreasury");
    address internal team = makeAddr("teamTreasury");
    address internal guardian = makeAddr("pauseGuardian");
    address internal companyPayee = makeAddr("companyPayee");
    address internal artistPayee = makeAddr("artistPayee");
    address internal designerPayee = makeAddr("designerPayee");

    function _deployAndOpen(uint256 seedWord) internal {
        WETHMock impl = new WETHMock();
        vm.etch(WETH, address(impl).code);

        coord = new VRFCoordinatorV2PlusMock();
        splitter = new CypherPunksSplitter(payable(companyPayee), payable(artistPayee), payable(designerPayee), makeAddr("payeeAdmin"));

        uint64 nonce = vm.getNonce(address(this));
        address predictedAH = vm.computeCreateAddress(address(this), nonce + 1);
        token = new CypherPunksToken(
            predictedAH, artist, team, address(coord),
            keccak256("kh"), 1, IDescriptor(address(0))
        );
        ah = new CypherPunksAuctionHouse(token, address(splitter), guardian);

        uint256 id = token.requestSeed();
        coord.fulfill(id, seedWord);
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();
        ah.startAuctions();
    }

    /// Drive one full day: single bid at `amount`, warp past end, settle.
    /// Returns the settled hammer price.
    function _settleDayWithBid(address bidder, uint256 amount, bytes32 entropy)
        internal
        returns (uint256 hammer)
    {
        uint256 tokenId = ah.auction().tokenId;
        vm.deal(bidder, amount);
        vm.prank(bidder);
        ah.createBid{value: amount}(tokenId);
        hammer = amount;

        vm.warp(uint256(ah.auction().endTime));
        vm.prevrandao(entropy);
        ah.settleCurrentAndCreateNewAuction();
    }
}
