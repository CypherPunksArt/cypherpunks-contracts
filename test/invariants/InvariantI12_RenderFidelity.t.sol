// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DescriptorFixture} from "../helpers/DescriptorFixture.sol";

/// I12 — Render fidelity.
/// tokenURI output for all 10,000 pieces is deterministic and pixel-identical
/// to the design files. (Render all, decode SVGs, image-diff against the
/// frozen renders, zero tolerance.)
///
/// STATUS: LIVE (Phase 8). The art-pending skip is gone — the real
/// Descriptor renders the Step 0 pixel-proven art pages. The full 10,000
/// render-all needs ffi for the off-chain SVG decode + pixel diff, so it
/// runs under the i12 profile:
///
///   FOUNDRY_PROFILE=i12 forge test --match-test I12_PixelDiffAllPieces
///
/// In the default profile (no ffi) that one test skips with a loud notice —
/// an ENVIRONMENT gate, not an art gate. Determinism runs everywhere.
contract InvariantI12_RenderFidelity is DescriptorFixture {
    using Strings for uint256;

    uint256 internal constant PIECES = 10_000;
    uint256 internal constant CHUNK = 500;
    string internal constant SCRATCH = "cache/i12/tokenuris.tsv";

    function setUp() public {
        _deployDescriptor();
    }

    /// Determinism half of I12: tokenURI is a pure function of
    /// (tokenId, pieceId) — two calls return identical bytes. Runs in the
    /// fast suite against the REAL Descriptor and art.
    function test_I12_TokenURIDeterministic() public view {
        uint256[3] memory ids = [uint256(0), 2_119, 9_999];
        for (uint256 i = 0; i < ids.length; i++) {
            string memory a = descriptor.tokenURI(ids[i] + 1, ids[i]);
            string memory b = descriptor.tokenURI(ids[i] + 1, ids[i]);
            assertEq(keccak256(bytes(a)), keccak256(bytes(b)), "non-deterministic");
        }
    }

    /// Pixel-diff render-all: every piece's tokenURI decoded and image-diffed
    /// against the frozen renders with zero tolerance, plus full attribute
    /// and display-convention verification (tools/art/verify_tokenuris.py).
    function test_I12_PixelDiffAllPieces() public {
        if (!_ffiAvailable()) {
            emit log(
                "I12 render-all SKIPPED: needs ffi -> run "
                "FOUNDRY_PROFILE=i12 forge test --match-test I12_PixelDiffAllPieces"
            );
            vm.skip(true);
            return;
        }
        vm.createDir("cache/i12", true);
        uint256 verified = 0;
        for (uint256 start = 0; start < PIECES; start += CHUNK) {
            // fresh chunk file
            if (vm.exists(SCRATCH)) vm.removeFile(SCRATCH);
            for (uint256 pieceId = start; pieceId < start + CHUNK; pieceId++) {
                // external self-call: each render gets a fresh memory frame,
                // otherwise 10,000 x ~250KB of never-freed test memory sends
                // the EVM's quadratic memory cost through the gas limit
                this.renderOne(pieceId);
            }
            string[] memory cmd = new string[](3);
            cmd[0] = "python3";
            cmd[1] = "tools/art/verify_tokenuris.py";
            cmd[2] = SCRATCH;
            bytes memory reply = vm.ffi(cmd);
            // expect "OK <CHUNK>"
            assertEq(
                keccak256(reply),
                keccak256(bytes(string.concat("OK ", CHUNK.toString()))),
                string.concat("verifier: ", string(reply))
            );
            verified += CHUNK;
        }
        if (vm.exists(SCRATCH)) vm.removeFile(SCRATCH);
        assertEq(verified, PIECES, "render-all incomplete");
        emit log("I12 GREEN: 10,000/10,000 tokenURIs pixel-identical to the frozen renders");
    }

    /// One piece per call frame (see loop comment). tokenId is display-only
    /// (name); pieceId+1 exercises both name branches across the run.
    function renderOne(uint256 pieceId) external {
        uint256 tokenId = pieceId + 1;
        vm.writeLine(
            SCRATCH,
            string.concat(
                tokenId.toString(),
                "\t",
                pieceId.toString(),
                "\t",
                descriptor.tokenURI(tokenId, pieceId)
            )
        );
    }

    function _ffiAvailable() internal returns (bool ok) {
        string[] memory probe = new string[](2);
        probe[0] = "echo";
        probe[1] = "i12";
        try vm.ffi(probe) returns (bytes memory out) {
            ok = keccak256(out) == keccak256(bytes("i12"));
        } catch {
            ok = false;
        }
    }
}
