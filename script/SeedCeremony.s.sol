// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DeployConfig, DeployLib} from "./DeployConfig.sol";
import {CypherPunksToken} from "../src/Token.sol";
import {CypherPunksAuctionHouse} from "../src/AuctionHouse.sol";
import {CypherPunksSplitter} from "../src/Splitter.sol";
import {ReservedDraw} from "../src/lib/ReservedDraw.sol";
import {VRFCoordinatorV2PlusMock} from "../test/helpers/VRFCoordinatorV2PlusMock.sol";
import {WETHMock} from "../test/helpers/Fixture.sol";
import {DescriptorStub} from "../test/helpers/DescriptorStub.sol";

/// Seed-ceremony rehearsal (doc §09), scripted and repeatable. On a mainnet
/// fork (or locally) it runs the full genesis flow — deploy → requestSeed →
/// fulfillment → four-step permissionless machine from four callers →
/// auction #1 → bids → first settlement chains auction #2 → proceeds release —
/// TWICE from clean state, asserting identical structural outcomes under
/// different seeds, and emits the transcript we will publish at real genesis.
///
/// Fulfillment is driven through a mock coordinator (test/helpers), because a
/// real Chainlink fulfillment cannot be forced on a fork. Everything else is
/// the production code path.
///
/// Run:  forge script script/SeedCeremony.s.sol
contract SeedCeremony is Script {
    struct Outcome {
        uint256 seed;
        uint16 reservedFirst;
        uint16 reservedLast;
        uint256 firstHammer;
        uint256 auctionOneId;
        uint256 auctionTwoId;
        uint256 splitterBalanceAfterSettle;
    }

    function run() external {
        console2.log("################################################################");
        console2.log("#   CYPHERPUNKS SEED CEREMONY REHEARSAL  (doc SS09)             #");
        console2.log("#   Two clean runs, different seeds, identical structure        #");
        console2.log("################################################################");

        Outcome memory a = _runOnce(1, uint256(keccak256("ceremony seed A")));
        Outcome memory b = _runOnce(2, uint256(keccak256("ceremony seed B")));

        // --- identical structural outcomes, different seeds ---
        require(a.seed != b.seed, "ceremony: seeds identical");
        require(a.auctionOneId == b.auctionOneId && a.auctionOneId == 1, "ceremony: auction #1");
        require(a.auctionTwoId == b.auctionTwoId && a.auctionTwoId == 2, "ceremony: chain to #2");
        require(a.firstHammer == b.firstHammer, "ceremony: hammer differs");
        require(
            a.splitterBalanceAfterSettle == b.splitterBalanceAfterSettle,
            "ceremony: proceeds differ"
        );
        // different seeds must actually reshuffle the reserved draw
        require(
            a.reservedFirst != b.reservedFirst || a.reservedLast != b.reservedLast,
            "ceremony: seed had no effect on reserved draw"
        );

        console2.log("");
        console2.log(">>> BOTH RUNS STRUCTURALLY IDENTICAL, SEEDS DISTINCT - REHEARSAL PASS");
    }

    function _runOnce(uint256 runNo, uint256 seedWord) internal returns (Outcome memory o) {
        o.seed = seedWord;

        // clean state: fresh WETH + coordinator + system each run
        WETHMock impl = new WETHMock();
        vm.etch(DeployLib.WETH, address(impl).code);
        VRFCoordinatorV2PlusMock coord = new VRFCoordinatorV2PlusMock();

        DeployConfig memory c = _ceremonyConfig(address(coord), runNo);
        address deployer = makeAddr(string.concat("ceremonyDeployer", vm.toString(runNo)));

        vm.startPrank(deployer);
        DeployLib.Deployment memory d = DeployLib.deploy(c, deployer);
        vm.stopPrank();
        DeployLib.verify(d, c);

        console2.log("");
        console2.log("=================== CEREMONY RUN", runNo, "===================");
        console2.log("Deployer        ", deployer);
        console2.log("Token           ", address(d.token));
        console2.log("AuctionHouse    ", address(d.auctionHouse));
        console2.log("Splitter        ", address(d.splitter));

        _seedAndGenesis(d, coord, seedWord, o);
        _firstAuction(d, c, runNo, o);
    }

    function _ceremonyConfig(address coord, uint256 runNo)
        internal
        returns (DeployConfig memory c)
    {
        string memory n = vm.toString(runNo);
        c = DeployConfig({
            treasury: makeAddr(string.concat("treasurySafe", n)),
            artist: makeAddr(string.concat("artistWallet", n)),
            designer: makeAddr(string.concat("designerWallet", n)),
            payeeAdmin: makeAddr(string.concat("payeeAdminSafe", n)),
            reserveTreasury: makeAddr(string.concat("reserveSafe", n)),
            pauseGuardian: makeAddr(string.concat("guardianSafe", n)),
            vrfCoordinator: coord,
            vrfKeyHash: keccak256("gas lane"),
            vrfSubId: 42,
            // rehearsal uses a stub; the REAL Descriptor (Phase 8) is deployed
            // first at mainnet genesis — validate now rejects a zero descriptor
            descriptor: address(new DescriptorStub())
        });
    }

    function _seedAndGenesis(
        DeployLib.Deployment memory d,
        VRFCoordinatorV2PlusMock coord,
        uint256 seedWord,
        Outcome memory o
    ) internal {
        uint256 g = gasleft();
        vm.prank(makeAddr("anyoneRequests"));
        uint256 reqId = d.token.requestSeed();
        console2.log("requestSeed gas ", g - gasleft());

        // mock coordinator calls rawFulfillRandomWords as itself → gate met
        g = gasleft();
        coord.fulfill(reqId, seedWord);
        console2.log("fulfill gas     ", g - gasleft());
        console2.log("SEED            ", d.token.seed());

        (uint16[100] memory artistSet, uint16[100] memory teamSet) = ReservedDraw.draw(seedWord);
        o.reservedFirst = artistSet[0];
        o.reservedLast = teamSet[99];
        console2.log("reserved[0]   (artist first piece)", uint256(artistSet[0]));
        console2.log("reserved[199] (team last piece)   ", uint256(teamSet[99]));

        // four-step permissionless machine, four different callers
        g = gasleft();
        vm.prank(makeAddr("caller1"));
        d.token.materializeBlob();
        console2.log("1 materializeBlob gas", g - gasleft());
        g = gasleft();
        vm.prank(makeAddr("caller2"));
        d.token.mintArtistTail();
        console2.log("2 mintArtistTail gas ", g - gasleft());
        g = gasleft();
        vm.prank(makeAddr("caller3"));
        d.token.mintTeamTail();
        console2.log("3 mintTeamTail gas   ", g - gasleft());
        g = gasleft();
        vm.prank(makeAddr("caller4"));
        d.auctionHouse.startAuctions();
        console2.log("4 startAuctions gas  ", g - gasleft());

        require(d.token.genesisComplete(), "ceremony: genesis incomplete");
        o.auctionOneId = d.auctionHouse.auction().tokenId;
    }

    function _firstAuction(
        DeployLib.Deployment memory d,
        DeployConfig memory c,
        uint256 runNo,
        Outcome memory o
    ) internal {
        // Both tails custodied by the reserve Safe; the artist payee wallet
        // holds NO tokens — it only ever receives the 5% splitter stream.
        require(d.token.balanceOf(c.reserveTreasury) == 200, "ceremony: reserve tail count");
        require(d.token.balanceOf(c.artist) == 0, "ceremony: artist payee holds tokens");

        address bidder1 = makeAddr("bidder1");
        address bidder2 = makeAddr("bidder2");
        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        d.auctionHouse.createBid{value: 1 ether}(1);
        vm.deal(bidder2, 2 ether);
        vm.prank(bidder2);
        d.auctionHouse.createBid{value: 2 ether}(1); // outbid; bidder1 refunded inline
        o.firstHammer = 2 ether;

        vm.warp(uint256(d.auctionHouse.auction().endTime));
        vm.prevrandao(keccak256(abi.encode("settle randao", runNo)));
        vm.prank(makeAddr("anySettler"));
        d.auctionHouse.settleCurrentAndCreateNewAuction();

        require(d.token.ownerOf(1) == bidder2, "ceremony: winner not token owner");
        o.auctionTwoId = d.auctionHouse.auction().tokenId;
        o.splitterBalanceAfterSettle = address(d.splitter).balance;

        d.splitter.release(payable(c.treasury));
        d.splitter.release(payable(c.artist));
        console2.log("auction #1 winner       ", bidder2);
        console2.log("hammer -> splitter (wei)", o.splitterBalanceAfterSettle);
        console2.log("treasury 95% (wei)      ", c.treasury.balance);
        console2.log("artist   5% (wei)       ", c.artist.balance);
        console2.log("chained to auction #    ", o.auctionTwoId);
    }
}
