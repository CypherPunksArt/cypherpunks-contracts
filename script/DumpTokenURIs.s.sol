// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Descriptor} from "../src/Descriptor.sol";
import {DescriptorData} from "../src/gen/DescriptorData.sol";
import {SSTORE2} from "../src/lib/SSTORE2.sol";

/// QA helper (tools/art/make_qa_gallery.py drives this): deploys the real
/// Descriptor from the encoded art pages and dumps "tokenId\tpieceId\turi"
/// for every id listed in cache/i12/qa-targets.txt (one per line) to
/// cache/i12/qa-tokenuris.tsv. Local simulation only — never broadcast.
///
///   FOUNDRY_PROFILE=i12 forge script script/DumpTokenURIs.s.sol
contract DumpTokenURIs is Script {
    using Strings for uint256;

    string internal constant TARGETS = "cache/i12/qa-targets.txt";
    string internal constant OUT = "cache/i12/qa-tokenuris.tsv";

    function run() external {
        address[] memory artPages =
            new address[](DescriptorData.ART_PAGE_COUNT);
        for (uint256 i = 0; i < artPages.length; i++) {
            artPages[i] = SSTORE2.write(_pageData("art-page-", i));
        }
        address[] memory piecePages =
            new address[](DescriptorData.PIECE_PAGE_COUNT);
        for (uint256 i = 0; i < piecePages.length; i++) {
            piecePages[i] = SSTORE2.write(_pageData("piece-page-", i));
        }
        Descriptor d =
            new Descriptor(artPages, piecePages, SSTORE2.write(_pageData("meta-page-", 0)));

        if (vm.exists(OUT)) vm.removeFile(OUT);
        string[] memory ids = vm.split(vm.trim(vm.readFile(TARGETS)), "\n");
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = vm.parseUint(vm.trim(ids[i]));
            uint256 pieceId = tokenId - 1;
            vm.writeLine(
                OUT,
                string.concat(
                    tokenId.toString(),
                    "\t",
                    pieceId.toString(),
                    "\t",
                    d.tokenURI(tokenId, pieceId)
                )
            );
        }
    }

    function _pageData(string memory prefix, uint256 i)
        internal
        view
        returns (bytes memory)
    {
        return vm.parseBytes(
            string.concat(
                "0x",
                vm.readFile(
                    string.concat(
                        "script/descriptor-data/", prefix, vm.toString(i), ".hex"
                    )
                )
            )
        );
    }
}
