// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Descriptor} from "../src/Descriptor.sol";
import {DescriptorData} from "../src/gen/DescriptorData.sol";
import {DescriptorFixture} from "./helpers/DescriptorFixture.sol";
import {SSTORE2} from "../src/lib/SSTORE2.sol";

/// Phase 8 gas report inputs (doc: everything vs the 16.78M EIP-7825 tx
/// cap). Run with -vv to read the numbers; the assertions pin the cap with
/// headroom so a regression fails loudly.
contract DescriptorGasTest is DescriptorFixture {
    uint256 internal constant TX_CAP = 16_780_000;

    // From script/descriptor-data/encode-summary.json + the binding
    // manifest: total RLE run counts per piece — min 177 (piece 7174),
    // median 314 (piece 1197), max 693 (piece 4172: Mocha / Spot Puffer /
    // Viking Helmet / Brown / Pizza / Flame Thrower).
    uint256 internal constant PIECE_MEDIAN = 1_197;
    uint256 internal constant PIECE_WORST = 4_172;

    function setUp() public {
        _deployDescriptor();
    }

    /// Per-page SSTORE2 write gas (each page is its own deploy tx; the
    /// intrinsic 21k + calldata of a real tx are added in the report).
    function test_Gas_PageWrites() public {
        string[3] memory kinds = ["art-page-", "piece-page-", "meta-page-"];
        uint256[3] memory counts = [
            DescriptorData.ART_PAGE_COUNT,
            DescriptorData.PIECE_PAGE_COUNT,
            uint256(1)
        ];
        uint256 total = 0;
        for (uint256 k = 0; k < 3; k++) {
            for (uint256 i = 0; i < counts[k]; i++) {
                bytes memory data = _pageData(kinds[k], i);
                uint256 g0 = gasleft();
                SSTORE2.write(data);
                uint256 used = g0 - gasleft();
                total += used;
                emit log_named_uint(
                    string.concat("write ", kinds[k], vm.toString(i), " gas"),
                    used
                );
                assertLt(used + 100_000, TX_CAP, "page write must fit one tx");
            }
        }
        emit log_named_uint("all page writes gas (sum, excl. tx intrinsic)", total);
    }

    function test_Gas_DescriptorDeploy() public {
        uint256 g0 = gasleft();
        Descriptor d = new Descriptor(artPages, piecePages, metaPage);
        uint256 used = g0 - gasleft();
        emit log_named_uint("Descriptor deploy gas", used);
        assertLt(used + 100_000, TX_CAP, "descriptor deploy must fit one tx");
        assertTrue(address(d) != address(0));
    }

    function test_Gas_TokenURI_MedianAndWorst() public {
        uint256 g0 = gasleft();
        descriptor.tokenURI(PIECE_MEDIAN + 1, PIECE_MEDIAN);
        uint256 median = g0 - gasleft();
        emit log_named_uint("tokenURI median-piece gas", median);

        g0 = gasleft();
        descriptor.tokenURI(PIECE_WORST + 1, PIECE_WORST);
        uint256 worst = g0 - gasleft();
        emit log_named_uint("tokenURI worst-piece gas", worst);

        // view-only surface, but keep it visibly bounded anyway
        assertLt(worst, TX_CAP, "worst render above tx cap");
        assertLe(median, worst, "median above worst?");
    }
}
