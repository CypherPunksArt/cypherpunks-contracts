// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DeployConfig, DeployLib} from "./DeployConfig.sol";

/// Production deploy script. Reads a single explicit config from env, deploys
/// the system in §05 lock order, then runs the post-deploy assertion block
/// (deploy-time twin of I14/I11) — failing loudly on any mismatch.
///
/// Usage (dry run):
///   forge script script/Deploy.s.sol --fork-url $MAINNET_RPC
/// Broadcast:
///   forge script script/Deploy.s.sol --fork-url $MAINNET_RPC --broadcast
///
/// Required env (validate() rejects a zero/unset value for ALL of these —
/// CP_DESCRIPTOR included; the Descriptor must be deployed first):
///   CP_TREASURY, CP_ARTIST, CP_DESIGNER, CP_PAYEE_ADMIN, CP_RESERVE_TREASURY,
///   CP_PAUSE_GUARDIAN, CP_VRF_COORDINATOR, CP_VRF_KEYHASH, CP_VRF_SUBID,
///   CP_DESCRIPTOR
///
/// CP_ARTIST and CP_DESIGNER are the splitter 5% payees ONLY. CP_PAYEE_ADMIN
/// is the company Safe that may rotate either behind a 48h timelock (key-loss
/// recovery); it must not be CP_ARTIST or CP_DESIGNER. Both genesis tails (the 100 artists-allocation
/// grants + the 100 team pieces) mint to CP_RESERVE_TREASURY — the project
/// Safe — for manual distribution.
contract Deploy is Script {
    function run() external returns (DeployLib.Deployment memory d) {
        DeployConfig memory c = _configFromEnv();

        address deployer = msg.sender;
        DeployLib.validate(c, deployer);

        vm.startBroadcast();
        d = DeployLib.deploy(c, deployer);
        vm.stopBroadcast();

        DeployLib.verify(d, c);

        console2.log("== CypherPunks deployed (verified) ==");
        console2.log("Token       ", address(d.token));
        console2.log("AuctionHouse", address(d.auctionHouse));
        console2.log("Splitter    ", address(d.splitter));
        console2.log("Next step: requestSeed() (permissionless, post-deploy)");
    }

    function _configFromEnv() internal view returns (DeployConfig memory c) {
        c.treasury = vm.envAddress("CP_TREASURY");
        c.artist = vm.envAddress("CP_ARTIST");
        c.designer = vm.envAddress("CP_DESIGNER");
        c.payeeAdmin = vm.envAddress("CP_PAYEE_ADMIN");
        c.reserveTreasury = vm.envAddress("CP_RESERVE_TREASURY");
        c.pauseGuardian = vm.envAddress("CP_PAUSE_GUARDIAN");
        c.vrfCoordinator = vm.envAddress("CP_VRF_COORDINATOR");
        c.vrfKeyHash = vm.envBytes32("CP_VRF_KEYHASH");
        c.vrfSubId = vm.envUint("CP_VRF_SUBID");
        c.descriptor = vm.envOr("CP_DESCRIPTOR", address(0));
    }
}
