// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {CypherPunksSplitter} from "../../src/Splitter.sol";

/// Fuzzed-actor handler for the Splitter accounting invariants (audit F3):
/// random funding, per-role release, artist/designer rotation
/// (propose -> 48h -> execute), and time warps. Tracks the ghost total of ETH ever received so the invariant
/// suite can check conservation and no-overpay.
contract SplitterHandler is CommonBase, StdCheats, StdUtils {
    CypherPunksSplitter public split;
    address payable public company;
    address payable public artist; // current artist (moves on rotation)
    address payable public designer; // current designer (moves on rotation)
    address public admin;

    uint256 public ghostReceived; // total ETH ever credited to the splitter

    constructor(
        CypherPunksSplitter _split,
        address payable _company,
        address payable _artist,
        address payable _designer,
        address _admin
    ) {
        split = _split;
        company = _company;
        artist = _artist;
        designer = _designer;
        admin = _admin;
    }

    /// Credit the splitter with ETH (models auction proceeds arriving).
    function fund(uint256 amtSeed) external {
        uint256 amt = bound(amtSeed, 0, 100 ether);
        vm.deal(address(split), address(split).balance + amt);
        ghostReceived += amt;
    }

    function releaseCompany() external {
        if (split.releasable(company) > 0) split.release(company);
    }

    function releaseArtist() external {
        if (split.releasable(artist) > 0) split.release(artist);
    }

    function releaseDesigner() external {
        if (split.releasable(designer) > 0) split.release(designer);
    }

    /// Rotate the artist payee through the real timelock. try/catch absorbs the
    /// documented guards (zero / company / current-artist).
    function rotate(uint256 seed) external {
        address payable na = payable(address(uint160(uint256(keccak256(abi.encode("na", seed))))));
        if (na == address(0)) return;
        vm.prank(admin);
        try split.proposeArtistUpdate(na) {} catch { return; }
        vm.warp(block.timestamp + split.ARTIST_UPDATE_DELAY());
        try split.executeArtistUpdate() { artist = na; } catch {}
    }

    /// Rotate the designer payee through the real timelock, same shape.
    function rotateDesigner(uint256 seed) external {
        address payable nd = payable(address(uint160(uint256(keccak256(abi.encode("nd", seed))))));
        if (nd == address(0)) return;
        vm.prank(admin);
        try split.proposeDesignerUpdate(nd) {} catch { return; }
        vm.warp(block.timestamp + split.ARTIST_UPDATE_DELAY());
        try split.executeDesignerUpdate() { designer = nd; } catch {}
    }

    function warp(uint256 s) external {
        vm.warp(block.timestamp + bound(s, 1, 30 days));
    }
}
