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
///
/// Live-audit CP-LIVE-05: funding goes through a real value transfer so
/// receive() is exercised and the ghost only moves on success, and the two
/// self-release roles are called from the payee address the way production
/// requires (msg.sender == account) instead of from the handler, where they
/// silently reverted in >95% of runs. Success counters let the suite assert
/// the coverage actually happened.
contract SplitterHandler is CommonBase, StdCheats, StdUtils {
    CypherPunksSplitter public split;
    address payable public company;
    address payable public artist; // current artist (moves on rotation)
    address payable public designer; // current designer (moves on rotation)
    address public admin;

    uint256 public ghostReceived; // total ETH ever credited to the splitter
    uint256 public fundCount; // successful value transfers in
    uint256 public releaseCount; // successful releases out
    uint256 public rotateCount; // matured rotations executed

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

    /// Credit the splitter with ETH (models auction proceeds arriving) through
    /// a real transfer, so the ghost can only move when the contract accepted it.
    function fund(uint256 amtSeed) external {
        uint256 amt = bound(amtSeed, 0, 100 ether);
        if (amt == 0) return;
        vm.deal(address(this), address(this).balance + amt);
        (bool ok,) = address(split).call{value: amt}("");
        if (!ok) return;
        ghostReceived += amt;
        fundCount++;
    }

    /// The company share is permissionless: anyone may push it.
    function releaseCompany() external {
        if (split.releasable(company) == 0) return;
        split.release(company);
        releaseCount++;
    }

    /// Artist and designer are self-release only, so impersonate the payee.
    function releaseArtist() external {
        if (split.releasable(artist) == 0) return;
        vm.prank(artist);
        split.release(artist);
        releaseCount++;
    }

    function releaseDesigner() external {
        if (split.releasable(designer) == 0) return;
        vm.prank(designer);
        split.release(designer);
        releaseCount++;
    }

    /// Rotate the artist payee through the real timelock. try/catch absorbs the
    /// documented guards (zero / company / current-artist).
    function rotate(uint256 seed) external {
        address payable na = payable(address(uint160(uint256(keccak256(abi.encode("na", seed))))));
        if (na == address(0)) return;
        vm.prank(admin);
        try split.proposeArtistUpdate(na) {} catch { return; }
        vm.warp(block.timestamp + split.ARTIST_UPDATE_DELAY());
        try split.executeArtistUpdate() {
            artist = na;
            rotateCount++;
        } catch {}
    }

    /// Rotate the designer payee through the real timelock, same shape.
    function rotateDesigner(uint256 seed) external {
        address payable nd = payable(address(uint160(uint256(keccak256(abi.encode("nd", seed))))));
        if (nd == address(0)) return;
        vm.prank(admin);
        try split.proposeDesignerUpdate(nd) {} catch { return; }
        vm.warp(block.timestamp + split.ARTIST_UPDATE_DELAY());
        try split.executeDesignerUpdate() {
            designer = nd;
            rotateCount++;
        } catch {}
    }

    function warp(uint256 s) external {
        vm.warp(block.timestamp + bound(s, 1, 30 days));
    }

    receive() external payable {}
}
