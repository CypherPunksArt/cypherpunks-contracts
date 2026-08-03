// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDescriptor} from "./interfaces/IDescriptor.sol";
import {SSTORE2} from "./lib/SSTORE2.sol";
import {DescriptorData} from "./gen/DescriptorData.sol";

/// @title Descriptor
/// @notice On-chain renderer for the 10,000 CypherPunks (doc §02 row 3:
///         Nouns Descriptor V2 pattern — SSTORE2 + RLE — adapted to the
///         Rev 7 schema: 40×40 grid, z-order Background → Body → Clothing →
///         Head → Earring → Eyes → Mouth → Accessory, Gender as element-set
///         selector, flat-colour background). tokenURI output is a fully
///         self-contained data URI (JSON + SVG), zero external references.
///
///         Immutability (I11): no owner, no setters, no privileged calls of
///         any kind. Art lives in pre-deployed SSTORE2 pages whose contents
///         the constructor pins by keccak256 code hash against generated
///         constants (src/gen/DescriptorData.sol); a wrong or tampered page
///         cannot construct. Storage is written once, in the constructor,
///         and no mutating function exists.
///
///         The three semi-transparent mouth colours are carried VERBATIM:
///         palette entries keep their raw alpha byte (128) and render as
///         8-digit hex (#RRGGBBAA) fills.
contract Descriptor is IDescriptor {
    using Strings for uint256;

    error PageCountMismatch();
    error PageHashMismatch(uint256 kind, uint256 index);
    error PieceOutOfRange();
    error DataCorrupt();

    /// Art category count and piece-record layout come from the generated
    /// data; the canvas and background are Rev 7 constants.
    string private constant SVG_HEAD =
        '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="640" '
        'viewBox="0 0 40 40" shape-rendering="crispEdges">'
        '<rect width="40" height="40" fill="#638596"/>';
    bytes16 private constant HEX = "0123456789abcdef";

    /// Written once in the constructor; no function mutates them.
    address[] private _artPages;
    address[] private _piecePages;
    address private immutable _metaPage;

    constructor(
        address[] memory artPages_,
        address[] memory piecePages_,
        address metaPage_
    ) {
        if (
            artPages_.length != DescriptorData.ART_PAGE_COUNT
                || piecePages_.length != DescriptorData.PIECE_PAGE_COUNT
        ) revert PageCountMismatch();
        for (uint256 i = 0; i < artPages_.length; i++) {
            if (artPages_[i].codehash != DescriptorData.artPageHash(i)) {
                revert PageHashMismatch(0, i);
            }
            _artPages.push(artPages_[i]);
        }
        for (uint256 i = 0; i < piecePages_.length; i++) {
            if (piecePages_[i].codehash != DescriptorData.piecePageHash(i)) {
                revert PageHashMismatch(1, i);
            }
            _piecePages.push(piecePages_[i]);
        }
        if (metaPage_.codehash != DescriptorData.META_PAGE_HASH) {
            revert PageHashMismatch(2, 0);
        }
        _metaPage = metaPage_;
    }

    /// @inheritdoc IDescriptor
    function tokenURI(uint256 tokenId, uint256 pieceId)
        external
        view
        returns (string memory)
    {
        if (pieceId >= DescriptorData.PIECE_COUNT) revert PieceOutOfRange();
        bytes memory rec = SSTORE2.read(
            _piecePages[pieceId / DescriptorData.PIECES_PER_PAGE],
            (pieceId % DescriptorData.PIECES_PER_PAGE) * 8,
            8
        );
        bool female = uint8(rec[0]) & 1 == 1;

        // Buffers with manual cursors: string.concat in a render loop is
        // quadratic in memory; the SVG worst case is bounded by the RLE run
        // count (max 327 runs/element, 7 layers).
        bytes memory svg = new bytes(140_000);
        uint256 svgLen = _append(svg, 0, bytes(SVG_HEAD));
        bytes memory attrs = new bytes(4_000);
        uint256 attrsLen = _append(
            attrs, 0, bytes('{"trait_type":"Background","value":"Punk"}')
        );

        for (uint256 i = 0; i < DescriptorData.CAT_COUNT; i++) {
            uint8 v = uint8(rec[1 + i]);
            if (v == 0xFF) continue;
            DescriptorData.Cat memory c = DescriptorData.cat(i);
            if (v >= c.valueCount) revert DataCorrupt();

            attrsLen = _append(attrs, attrsLen, bytes(',{"trait_type":"'));
            attrsLen = _append(attrs, attrsLen, bytes(c.name));
            attrsLen = _append(attrs, attrsLen, bytes('","value":"'));
            attrsLen = _appendLabel(attrs, attrsLen, c, v);
            attrsLen = _append(attrs, attrsLen, bytes('"}'));

            svgLen = _renderLayer(svg, svgLen, c, v, female);
        }
        attrsLen = _append(
            attrs,
            attrsLen,
            female
                ? bytes(',{"trait_type":"Gender","value":"Female"}')
                : bytes(',{"trait_type":"Gender","value":"Male"}')
        );
        // Genesis tail (token IDs 9,801-10,000) is marked by the Born
        // attribute; daily punks carry none (the token id is the birthday).
        if (tokenId > 9_800) {
            attrsLen = _append(
                attrs, attrsLen, bytes(',{"trait_type":"Born","value":"Genesis"}')
            );
        }
        svgLen = _append(svg, svgLen, bytes("</svg>"));

        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"',
                        _name(tokenId),
                        '","description":"CypherPunks create art through code.',
                        '","attributes":[',
                        _slice(attrs, attrsLen),
                        '],"image":"data:image/svg+xml;base64,',
                        Base64.encode(bytes(_slice(svg, svgLen))),
                        '"}'
                    )
                )
            )
        );
    }

    /// Display convention (Flag 3 ruling 2026-07-08, governs until folded
    /// into the next doc revision): "CypherPunk #N" uniform for all 10,000.
    /// The genesis tail is marked by the Born attribute, never the name.
    function _name(uint256 tokenId) private pure returns (string memory) {
        return string.concat("CypherPunk #", tokenId.toString());
    }

    /// value label: walk the category's length-prefixed label region.
    function _appendLabel(
        bytes memory buf,
        uint256 pos,
        DescriptorData.Cat memory c,
        uint8 v
    ) private view returns (uint256) {
        bytes memory labels = SSTORE2.read(_metaPage, c.labOff, c.labLen);
        uint256 p = 0;
        for (uint256 skip = 0; skip < v; skip++) {
            p += 1 + uint8(labels[p]);
        }
        uint256 len = uint8(labels[p]);
        for (uint256 i = 0; i < len; i++) {
            buf[pos + i] = labels[p + 1 + i];
        }
        return pos + len;
    }

    /// Decode one element's RLE blob into 1px-high SVG rects.
    function _renderLayer(
        bytes memory svg,
        uint256 pos,
        DescriptorData.Cat memory c,
        uint8 v,
        bool female
    ) private view returns (uint256) {
        uint256 imgIdx = uint8(
            SSTORE2.read(
                _metaPage, (female ? c.mapFemaleOff : c.mapMaleOff) + v, 1
            )[0]
        );
        if (imgIdx == 0xFF || imgIdx >= c.imgCount) revert DataCorrupt();
        bytes memory dir = SSTORE2.read(_metaPage, c.dirOff + imgIdx * 5, 5);
        bytes memory blob = SSTORE2.read(
            _artPages[uint8(dir[0])],
            (uint256(uint8(dir[1])) << 8) | uint8(dir[2]),
            (uint256(uint8(dir[3])) << 8) | uint8(dir[4])
        );

        Img memory im = Img({
            top: uint8(blob[0]),
            left: uint8(blob[1]),
            w: uint8(blob[3]),
            pal: uint8(blob[4]),
            x: 0,
            y: 0
        });
        uint256 p = 5 + im.pal * 4;
        if (blob.length < p || im.w == 0) revert DataCorrupt();

        while (p < blob.length) {
            if (p + 2 > blob.length) revert DataCorrupt();
            uint256 runLen = uint8(blob[p]);
            uint256 idx = uint8(blob[p + 1]);
            p += 2;
            if (runLen == 0 || idx > im.pal) revert DataCorrupt();
            if (idx != 0) {
                pos = _rect(svg, pos, im, runLen, blob, idx);
            }
            im.x += runLen;
            if (im.x > im.w) revert DataCorrupt();
            if (im.x == im.w) {
                im.x = 0;
                im.y++;
            }
        }
        if (im.x != 0) revert DataCorrupt();
        return pos;
    }

    struct Img {
        uint256 top;
        uint256 left;
        uint256 w;
        uint256 pal;
        uint256 x;
        uint256 y;
    }

    /// <rect x=".." y=".." width=".." height="1" fill="#rrggbb[aa]"/>
    function _rect(
        bytes memory svg,
        uint256 pos,
        Img memory im,
        uint256 runLen,
        bytes memory blob,
        uint256 palIdx
    ) private pure returns (uint256) {
        pos = _append(svg, pos, bytes('<rect x="'));
        pos = _num(svg, pos, im.left + im.x);
        pos = _append(svg, pos, bytes('" y="'));
        pos = _num(svg, pos, im.top + im.y);
        pos = _append(svg, pos, bytes('" width="'));
        pos = _num(svg, pos, runLen);
        pos = _append(svg, pos, bytes('" height="1" fill="#'));
        uint256 base = 5 + (palIdx - 1) * 4;
        uint8 a = uint8(blob[base + 3]);
        for (uint256 i = 0; i < (a == 255 ? 3 : 4); i++) {
            uint8 b = uint8(blob[base + i]);
            svg[pos++] = HEX[b >> 4];
            svg[pos++] = HEX[b & 0x0F];
        }
        pos = _append(svg, pos, bytes('"/>'));
        return pos;
    }

    /// 0..99 decimal (canvas coordinates and run widths are <= 40).
    function _num(bytes memory buf, uint256 pos, uint256 n)
        private
        pure
        returns (uint256)
    {
        if (n >= 100) revert DataCorrupt();
        if (n >= 10) {
            buf[pos++] = bytes1(uint8(48 + n / 10));
        }
        buf[pos++] = bytes1(uint8(48 + n % 10));
        return pos;
    }

    function _append(bytes memory buf, uint256 pos, bytes memory s)
        private
        pure
        returns (uint256)
    {
        if (pos + s.length > buf.length) revert DataCorrupt();
        assembly {
            mcopy(add(add(buf, 0x20), pos), add(s, 0x20), mload(s))
        }
        return pos + s.length;
    }

    function _slice(bytes memory buf, uint256 len)
        private
        pure
        returns (string memory out)
    {
        out = new string(len);
        assembly {
            mcopy(add(out, 0x20), add(buf, 0x20), len)
        }
    }

    /// Introspection for the deploy script / fork tests.
    function artPage(uint256 i) external view returns (address) {
        return _artPages[i];
    }

    function piecePage(uint256 i) external view returns (address) {
        return _piecePages[i];
    }

    function metaPage() external view returns (address) {
        return _metaPage;
    }
}
