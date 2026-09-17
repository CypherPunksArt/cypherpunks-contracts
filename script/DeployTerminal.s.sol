// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {AuctionTerminal} from "../src/AuctionTerminal.sol";

/// Deploys the onchain auction terminal.
///
/// The page is read from script/terminal.html, whose footer carries a
/// __TERMINAL_ADDRESS__ placeholder. The terminal's own address is predicted
/// from the deployer's nonce and substituted before deploy, so the stored
/// page names the very contract it lives in — a reader of ui() sees where
/// to retrieve the page they are reading.
///
///   forge script script/DeployTerminal.s.sol --rpc-url $RPC --broadcast \
///     --sender $DEPLOYER [--ledger | --private-key ...]
contract DeployTerminal is Script {
    function run() external returns (AuctionTerminal terminal) {
        string memory html = vm.readFile("script/terminal.html");
        // AT-09: exactly one placeholder — zero means the self-reference is
        // missing, two or more means the page has drifted from expectations.
        require(
            vm.split(html, "__TERMINAL_ADDRESS__").length == 2,
            "expected exactly one __TERMINAL_ADDRESS__ placeholder"
        );

        // the constructor's SSTORE2.write deploys the data contract from
        // INSIDE the terminal, so the terminal itself lands at the
        // deployer's current nonce.
        address predicted = vm.computeCreateAddress(msg.sender, vm.getNonce(msg.sender));
        html = vm.replace(html, "__TERMINAL_ADDRESS__", vm.toString(predicted));
        require(
            vm.indexOf(html, "__TERMINAL_ADDRESS__") == type(uint256).max,
            "placeholder survived replacement"
        );

        vm.startBroadcast();
        terminal = new AuctionTerminal(html);
        vm.stopBroadcast();

        require(address(terminal) == predicted, "address prediction mismatch");
        require(
            keccak256(bytes(terminal.ui())) == keccak256(bytes(html)),
            "stored page does not round-trip"
        );
    }
}
