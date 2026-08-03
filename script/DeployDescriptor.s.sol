// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Descriptor} from "../src/Descriptor.sol";
import {DescriptorData} from "../src/gen/DescriptorData.sol";
import {SSTORE2} from "../src/lib/SSTORE2.sol";

/// Phase 8 deploy: art pages then the Descriptor, per the pinned order
/// (doc §02: Descriptor → Token → AuctionHouse; the Descriptor address is
/// an immutable constructor param on the Token).
///
/// Each SSTORE2 page write is its own transaction (a ~24.5KB page costs
/// ~5.1M gas — well under the 16.78M tx cap; deploying all pages plus the
/// Descriptor in ONE tx would exceed it, so this script broadcasts them
/// separately). The Descriptor constructor re-verifies every page by
/// keccak256 code hash against the generated constants; a wrong page
/// cannot construct.
///
/// Usage (dry run / broadcast):
///   forge script script/DeployDescriptor.s.sol --fork-url $RPC [--broadcast]
/// Then export the printed address as CP_DESCRIPTOR for Deploy.s.sol.
contract DeployDescriptor is Script {
    string internal constant REAL_DIR = "script/descriptor-data";

    /// Art-dir selection. The real descriptor data may only construct on a
    /// fork/local chain (31337) or on mainnet at the real deploy. The
    /// Descriptor constructor's page-hash pinning independently rejects any
    /// art dir that doesn't match the compiled DescriptorData constants, so a
    /// dir/library mismatch cannot construct.
    string internal artDir;

    function run() external returns (Descriptor descriptor) {
        artDir = vm.envOr("CP_ART_DIR", string(REAL_DIR));
        require(keccak256(bytes(artDir)) == keccak256(bytes(REAL_DIR)), "CP_ART_DIR: unknown art dir");
        require(
            block.chainid == 1 || block.chainid == 31337,
            "REFUSED: descriptor-data is fork/mainnet-only"
        );

        vm.startBroadcast();
        address[] memory artPages = new address[](DescriptorData.ART_PAGE_COUNT);
        for (uint256 i = 0; i < artPages.length; i++) {
            artPages[i] = SSTORE2.write(_page("art-page-", i));
            console2.log("art page", i, artPages[i]);
        }
        address[] memory piecePages = new address[](DescriptorData.PIECE_PAGE_COUNT);
        for (uint256 i = 0; i < piecePages.length; i++) {
            piecePages[i] = SSTORE2.write(_page("piece-page-", i));
            console2.log("piece page", i, piecePages[i]);
        }
        address metaPage = SSTORE2.write(_page("meta-page-", 0));
        console2.log("meta page ", metaPage);

        descriptor = new Descriptor(artPages, piecePages, metaPage);
        vm.stopBroadcast();

        console2.log("== Descriptor deployed (pages hash-verified) ==");
        console2.log("CP_DESCRIPTOR", address(descriptor));
    }

    function _page(string memory prefix, uint256 i)
        private
        view
        returns (bytes memory)
    {
        return vm.parseBytes(
            string.concat(
                "0x",
                vm.readFile(
                    string.concat(artDir, "/", prefix, vm.toString(i), ".hex")
                )
            )
        );
    }
}
