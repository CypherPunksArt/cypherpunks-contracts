// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CypherPunksMailingList, CypherPunksTokenLike, CypherPunksAuctionHouseLike} from "../src/MailingList.sol";
import {CypherPunksPFP, IPunkToken} from "../src/PFP.sol";
import {CypherPunksManual} from "../src/Manual.sol";

/// Deploys the three auxiliary CypherPunks contracts (Mailing List, PFP registry,
/// User Manual) against an already-deployed Token + AuctionHouse. The manual text
/// is read from script/manual.txt so it can be reviewed/edited without touching
/// Solidity. Env: PK, TOKEN, AH. Broadcast:
///   forge script script/SocialDeploy.s.sol --rpc-url $RPC --broadcast --private-key $PK
contract SocialDeploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PK");
        address tokenAddr = vm.envAddress("TOKEN");
        address ahAddr = vm.envAddress("AH");
        string memory manualText = vm.readFile("script/manual.txt");

        vm.startBroadcast(pk);

        CypherPunksMailingList mailingList = new CypherPunksMailingList(
            CypherPunksTokenLike(tokenAddr), CypherPunksAuctionHouseLike(ahAddr)
        );
        CypherPunksPFP pfp = new CypherPunksPFP(IPunkToken(tokenAddr));
        CypherPunksManual manual = new CypherPunksManual(manualText);

        vm.stopBroadcast();

        console2.log("MAILING_LIST", address(mailingList));
        console2.log("PFP         ", address(pfp));
        console2.log("MANUAL      ", address(manual));
        console2.log("manual bytes", manual.length());
    }
}
