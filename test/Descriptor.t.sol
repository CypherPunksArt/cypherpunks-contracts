// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Descriptor} from "../src/Descriptor.sol";
import {DescriptorData} from "../src/gen/DescriptorData.sol";
import {DescriptorFixture} from "./helpers/DescriptorFixture.sol";

/// Descriptor unit tests (fast suite). Pixel-level fidelity for all 10,000
/// pieces is I12 (test/invariants/InvariantI12_RenderFidelity.t.sol, i12
/// profile); this file covers construction pinning, output shape, display
/// convention, determinism, and gas.
contract DescriptorTest is DescriptorFixture {
    function setUp() public {
        _deployDescriptor();
    }

    function test_ConstructorPinsPageHashes() public {
        // tamper: swap two art pages -> hash check must revert
        address[] memory badArt = new address[](artPages.length);
        for (uint256 i = 0; i < artPages.length; i++) {
            badArt[i] = artPages[i];
        }
        (badArt[0], badArt[1]) = (badArt[1], badArt[0]);
        vm.expectRevert(
            abi.encodeWithSelector(Descriptor.PageHashMismatch.selector, 0, 0)
        );
        new Descriptor(badArt, piecePages, metaPage);

        // wrong count
        address[] memory short_ = new address[](artPages.length - 1);
        for (uint256 i = 0; i < short_.length; i++) {
            short_[i] = artPages[i];
        }
        vm.expectRevert(Descriptor.PageCountMismatch.selector);
        new Descriptor(short_, piecePages, metaPage);
    }

    function test_TokenURI_SelfContainedDataUri() public view {
        string memory uri = descriptor.tokenURI(1, 0);
        bytes memory json = Base64.decode(_stripPrefix(uri));
        // decodes as JSON with the expected fields, image is an embedded SVG
        assertTrue(_contains(json, bytes('"name":"CypherPunk #1"')), "name");
        assertTrue(
            _contains(
                json,
                bytes('"description":"CypherPunks create art through code."')
            ),
            "description"
        );
        assertTrue(
            _contains(json, bytes('"trait_type":"Background","value":"Punk"')),
            "background attr"
        );
        assertTrue(
            _contains(json, bytes('"image":"data:image/svg+xml;base64,')),
            "embedded svg"
        );
        // zero external references of any kind
        assertFalse(_contains(json, bytes("http")), "no urls");
        assertFalse(_contains(json, bytes("ipfs")), "no ipfs");
    }

    /// Display convention (Flag 3 ruling 2026-07-08): name uniform for all
    /// ids — the genesis tail #9,801-#10,000 carries Born=Genesis instead,
    /// and daily punks carry no Born attribute.
    function test_TokenURI_GenesisTailName() public view {
        bytes memory walk = Base64.decode(_stripPrefix(descriptor.tokenURI(9_800, 42)));
        assertTrue(_contains(walk, bytes('"name":"CypherPunk #9800"')));
        assertFalse(_contains(walk, bytes('"trait_type":"Born"')), "walk has no Born");
        bytes memory tail = Base64.decode(_stripPrefix(descriptor.tokenURI(9_801, 42)));
        assertTrue(_contains(tail, bytes('"name":"CypherPunk #9801"')));
        assertFalse(_contains(tail, bytes("GENESIS")), "no GENESIS in name");
        assertTrue(
            _contains(tail, bytes('{"trait_type":"Born","value":"Genesis"}')),
            "tail Born attribute"
        );
    }

    function test_TokenURI_Deterministic() public view {
        assertEq(
            keccak256(bytes(descriptor.tokenURI(7, 4646))),
            keccak256(bytes(descriptor.tokenURI(7, 4646)))
        );
    }

    /// The three 50%-alpha mouth colours are carried verbatim: the SVG must
    /// contain an 8-digit hex fill ending in "80" (alpha 128). Piece 2119
    /// (punk 2120) wears mouth_focused.
    function test_TokenURI_SemiAlphaVerbatim() public view {
        bytes memory json = Base64.decode(_stripPrefix(descriptor.tokenURI(1, 2_119)));
        bytes memory svg = _extractSvg(json);
        assertTrue(_contains(svg, bytes('fill="#00000080"')), "verbatim alpha 128");
    }

    function test_TokenURI_RevertsOutOfRange() public {
        vm.expectRevert(Descriptor.PieceOutOfRange.selector);
        descriptor.tokenURI(1, 10_000);
    }

    function test_Gas_TokenURI() public {
        // piece 0 = typical; the worst-case piece is asserted in the gas
        // report (tools/art/gas_report: max total run count)
        uint256 g0 = gasleft();
        descriptor.tokenURI(1, 0);
        uint256 typical = g0 - gasleft();
        emit log_named_uint("tokenURI(piece 0) gas", typical);
        assertLt(typical, 30_000_000, "tokenURI runaway");
    }

    // helpers

    function _stripPrefix(string memory uri) internal pure returns (string memory) {
        bytes memory b = bytes(uri);
        bytes memory prefix = bytes("data:application/json;base64,");
        require(b.length > prefix.length, "short uri");
        for (uint256 i = 0; i < prefix.length; i++) {
            require(b[i] == prefix[i], "bad prefix");
        }
        bytes memory out = new bytes(b.length - prefix.length);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = b[prefix.length + i];
        }
        return string(out);
    }

    function _extractSvg(bytes memory json) internal pure returns (bytes memory) {
        bytes memory marker = bytes('"image":"data:image/svg+xml;base64,');
        int256 at = _find(json, marker);
        require(at >= 0, "no image field");
        uint256 start = uint256(at) + marker.length;
        uint256 end = start;
        while (end < json.length && json[end] != '"') end++;
        bytes memory b64 = new bytes(end - start);
        for (uint256 i = 0; i < b64.length; i++) {
            b64[i] = json[start + i];
        }
        return Base64.decode(string(b64));
    }

    function _contains(bytes memory hay, bytes memory needle) internal pure returns (bool) {
        return _find(hay, needle) >= 0;
    }

    function _find(bytes memory hay, bytes memory needle) internal pure returns (int256) {
        if (needle.length > hay.length) return -1;
        for (uint256 i = 0; i + needle.length <= hay.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (hay[i + j] != needle[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return int256(i);
        }
        return -1;
    }
}
