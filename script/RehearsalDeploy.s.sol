// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CypherPunksToken} from "../src/Token.sol";
import {CypherPunksAuctionHouse} from "../src/AuctionHouse.sol";
import {CypherPunksSplitter} from "../src/Splitter.sol";
import {IDescriptor} from "../src/interfaces/IDescriptor.sol";
import {VRFCoordinatorV2PlusMock} from "../test/helpers/VRFCoordinatorV2PlusMock.sol";

/// REHEARSAL DEPLOY — stands up a short-duration copy of the real contracts on
/// public Sepolia (mock VRF, zero descriptor → fallback tokenURI), driven
/// through the exact genesis state machine the tested WalkFixture uses. The
/// only deviation from mainnet is the DURATION/TIME_BUFFER constants (4min/1min)
/// so 10 live daily cycles fit in ~40 minutes instead of 10 days. Broadcast:
///   forge script script/RehearsalDeploy.s.sol --rpc-url $RPC --broadcast --private-key $PK
contract RehearsalDeploy is Script {
    // distinct, nonzero role addresses (single-Safe config: company == admin == guardian)
    address constant ARTIST = 0x000000000000000000000000000000000000dEaD;
    address constant DESIGNER = 0x000000000000000000000000000000000dE51E9D;
    address constant TEAM   = 0x000000000000000000000000000000000000bEEF;

    function run() external {
        uint256 pk = vm.envUint("PK");
        address deployer = vm.addr(pk);
        uint256 seedWord = uint256(keccak256("cypherpunks sepolia rehearsal"));

        vm.startBroadcast(pk);

        VRFCoordinatorV2PlusMock coord = new VRFCoordinatorV2PlusMock();

        // company == payeeAdmin == deployer (allowed: only payeeAdmin==artist is forbidden)
        CypherPunksSplitter splitter =
            new CypherPunksSplitter(payable(deployer), payable(ARTIST), payable(DESIGNER), deployer);

        uint64 nonce = vm.getNonce(deployer);
        address predictedAH = vm.computeCreateAddress(deployer, nonce + 1);
        CypherPunksToken token = new CypherPunksToken(
            predictedAH, ARTIST, TEAM, address(coord),
            keccak256("rehearsal-kh"), 1, IDescriptor(address(0))
        );
        CypherPunksAuctionHouse ah =
            new CypherPunksAuctionHouse(token, address(splitter), deployer);
        require(address(ah) == predictedAH, "AH address prediction mismatch");

        // genesis state machine (I17): seed -> materialize -> reserved mints -> open
        uint256 id = token.requestSeed();
        coord.fulfill(id, seedWord);
        token.materializeBlob();
        token.mintArtistTail();
        token.mintTeamTail();
        ah.startAuctions();

        vm.stopBroadcast();

        console2.log("COORD   ", address(coord));
        console2.log("SPLITTER", address(splitter));
        console2.log("TOKEN   ", address(token));
        console2.log("AH      ", address(ah));
        console2.log("auction#1 tokenId", ah.auction().tokenId);
        console2.log("auction#1 endTime", ah.auction().endTime);
    }
}
