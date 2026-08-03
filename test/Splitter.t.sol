// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Fixture} from "./helpers/Fixture.sol";
import {CypherPunksSplitter} from "../src/Splitter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC20Mock {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract RevertingPayee {
    function claim(CypherPunksSplitter s) external {
        s.release(payable(address(this)));
    }

    receive() external payable {
        revert("blocked");
    }
}

/// Splitter unit suite: fixed 90/5/5 pull-payment accounting for ETH and
/// ERC-20. Company release is permissionless; a rotatable payee (artist,
/// designer) may only release its own funds (audit H-02). No mutation surface.
contract SplitterTest is Test {
    CypherPunksSplitter internal split;
    address payable internal company = payable(makeAddr("company"));
    address payable internal artistP = payable(makeAddr("artistPayee"));
    address payable internal designerP = payable(makeAddr("designerPayee"));
    address internal admin = makeAddr("payeeAdmin");

    function setUp() public {
        split = new CypherPunksSplitter(company, artistP, designerP, admin);
    }

    // ---------------------------------------------------------- construction

    function test_Constructor_Validation() public {
        vm.expectRevert(bytes('company is zero'));
        new CypherPunksSplitter(payable(address(0)), artistP, designerP, admin);
        vm.expectRevert(bytes('artist is zero'));
        new CypherPunksSplitter(company, payable(address(0)), designerP, admin);
        vm.expectRevert(bytes('designer is zero'));
        new CypherPunksSplitter(company, artistP, payable(address(0)), admin);
        vm.expectRevert(bytes('admin is zero'));
        new CypherPunksSplitter(company, artistP, designerP, address(0));
        vm.expectRevert(bytes('payees identical'));
        new CypherPunksSplitter(company, company, designerP, admin);
        vm.expectRevert(bytes('payees identical'));
        new CypherPunksSplitter(company, artistP, payable(company), admin);
        vm.expectRevert(bytes('payees identical'));
        new CypherPunksSplitter(company, artistP, artistP, admin);
        vm.expectRevert(bytes('admin is artist'));
        new CypherPunksSplitter(company, artistP, designerP, artistP);
        vm.expectRevert(bytes('admin is designer'));
        new CypherPunksSplitter(company, artistP, designerP, designerP);
    }

    // audit F4 / single-Safe ruling (2026-07-20): payeeAdmin MAY equal the
    // company — one 3-of-5 team Safe fills both roles. Must deploy (disclosed
    // trust: the team can rotate the artist payee behind the 48h timelock).
    function test_Constructor_AllowsAdminEqualsCompany() public {
        CypherPunksSplitter s = new CypherPunksSplitter(company, artistP, designerP, company);
        assertEq(s.payeeAdmin(), company);
        assertEq(s.company(), company);
    }

    function test_SharesFixed() public {
        assertEq(split.shares(company), 90);
        assertEq(split.shares(artistP), 5);
        assertEq(split.shares(designerP), 5);
        assertEq(split.shares(makeAddr("stranger")), 0);
        assertEq(
            split.COMPANY_SHARES() + split.ARTIST_SHARES() + split.DESIGNER_SHARES(),
            split.TOTAL_SHARES()
        );
    }

    // ------------------------------------------------------------------ ETH

    function test_EthSplit_90_5_5() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(split).call{value: 1 ether}("");
        assertTrue(ok);

        assertEq(split.releasable(company), 0.9 ether);
        assertEq(split.releasable(artistP), 0.05 ether);
        assertEq(split.releasable(designerP), 0.05 ether);

        // company release is permissionless; a rotatable payee self-releases
        vm.prank(makeAddr("randomCaller"));
        split.release(company);
        vm.prank(artistP);
        split.release(artistP);
        vm.prank(designerP);
        split.release(designerP);

        assertEq(company.balance, 0.9 ether);
        assertEq(artistP.balance, 0.05 ether);
        assertEq(designerP.balance, 0.05 ether);
        assertEq(address(split).balance, 0);
    }

    function testFuzz_EthAccounting_NeverOverpays(uint96 a, uint96 b) public {
        uint256 first = bound(uint256(a), 1, 100 ether);
        uint256 second = bound(uint256(b), 1, 100 ether);

        vm.deal(address(this), first + second);
        (bool ok,) = address(split).call{value: first}("");
        assertTrue(ok);
        if (split.releasable(company) > 0) split.release(company);

        (ok,) = address(split).call{value: second}("");
        assertTrue(ok);
        if (split.releasable(company) > 0) split.release(company);
        if (split.releasable(artistP) > 0) { vm.prank(artistP); split.release(artistP); }
        if (split.releasable(designerP) > 0) { vm.prank(designerP); split.release(designerP); }

        uint256 total = first + second;
        // exact shares modulo integer-division dust, which stays in the pot
        assertEq(company.balance, (total * 90) / 100);
        assertLe(total - company.balance - artistP.balance - designerP.balance, 2);
        assertLe(address(split).balance, 2);
    }

    function test_DoubleRelease_Reverts() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(split).call{value: 1 ether}("");
        assertTrue(ok);
        split.release(company);
        vm.expectRevert(bytes('account is not due payment'));
        split.release(company);
    }

    function test_NonPayeeRelease_Reverts() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(split).call{value: 1 ether}("");
        assertTrue(ok);
        vm.expectRevert(bytes('account has no shares'));
        split.release(payable(makeAddr("stranger")));
    }

    /// A blocking payee strands only their own share (threat model row:
    /// pull-payment isolates payees). The blocked payee here is the artist, so
    /// it must claim for itself; its receive reverts, stranding only its 5%.
    function test_BlockingPayee_CannotBlockTheOthers() public {
        RevertingPayee blocked = new RevertingPayee();
        CypherPunksSplitter s2 =
            new CypherPunksSplitter(company, payable(address(blocked)), designerP, admin);

        vm.deal(address(this), 1 ether);
        (bool ok,) = address(s2).call{value: 1 ether}("");
        assertTrue(ok);

        // the blocked artist claiming for itself reverts on its own receive
        vm.expectRevert(bytes('payment failed'));
        blocked.claim(s2);

        s2.release(company);
        vm.prank(designerP);
        s2.release(designerP);
        assertEq(company.balance, 0.9 ether);
        assertEq(designerP.balance, 0.05 ether);
        // blocked share remains accounted and claimable if they stop reverting
        assertEq(s2.releasable(payable(address(blocked))), 0.05 ether);
    }

    // ---------------------------------------------------------------- ERC20

    function test_Erc20Split_90_5_5() public {
        ERC20Mock mock = new ERC20Mock();
        mock.mint(address(split), 1000 ether);

        assertEq(split.releasable(IERC20(address(mock)), company), 900 ether);
        assertEq(split.releasable(IERC20(address(mock)), artistP), 50 ether);
        assertEq(split.releasable(IERC20(address(mock)), designerP), 50 ether);

        vm.prank(makeAddr("randomCaller"));
        split.release(IERC20(address(mock)), company);
        vm.prank(artistP);
        split.release(IERC20(address(mock)), artistP);
        vm.prank(designerP);
        split.release(IERC20(address(mock)), designerP);

        assertEq(mock.balanceOf(company), 900 ether);
        assertEq(mock.balanceOf(artistP), 50 ether);
        assertEq(mock.balanceOf(designerP), 50 ether);

        vm.expectRevert(bytes('account is not due payment'));
        split.release(IERC20(address(mock)), company);
    }

    // ------------------------------------------------- artist rotation (48h)

    function _fund(uint256 amount) internal {
        vm.deal(address(this), amount);
        (bool ok,) = address(split).call{value: amount}("");
        assertTrue(ok);
    }

    function test_Rotation_OnlyAdminProposes() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(bytes('not payee admin'));
        split.proposeArtistUpdate(makeAddr("newArtist"));
    }

    function test_Rotation_ProposalGuards() public {
        vm.startPrank(admin);
        vm.expectRevert(bytes('new artist zero'));
        split.proposeArtistUpdate(address(0));
        vm.expectRevert(bytes('new artist is company'));
        split.proposeArtistUpdate(company);
        vm.expectRevert(bytes('new artist is designer'));
        split.proposeArtistUpdate(designerP);
        vm.expectRevert(bytes('new artist unchanged'));
        split.proposeArtistUpdate(artistP);
        vm.stopPrank();
    }

    function test_Rotation_TimelockGate() public {
        address newArtist = makeAddr("newArtist");
        vm.prank(admin);
        split.proposeArtistUpdate(newArtist);
        assertEq(split.pendingArtist(), newArtist);
        assertEq(split.artistUpdateExecutableAt(), block.timestamp + 48 hours);

        // premature execution reverts on time, not caller (permissionless)
        vm.prank(makeAddr("anyone"));
        vm.expectRevert(bytes('timelock not elapsed'));
        split.executeArtistUpdate();

        vm.warp(block.timestamp + 48 hours);
        vm.prank(makeAddr("anyone"));
        split.executeArtistUpdate();
        assertEq(split.artist(), newArtist);
        assertEq(split.pendingArtist(), address(0));
        assertEq(split.artistUpdateExecutableAt(), 0);
        assertEq(split.shares(newArtist), 5, "new artist inherits 5%");
        assertEq(split.shares(artistP), 0, "old artist loses the role");
    }

    function test_Rotation_AdminCanCancel() public {
        vm.prank(admin);
        split.proposeArtistUpdate(makeAddr("newArtist"));
        vm.prank(admin);
        split.cancelArtistUpdate();
        assertEq(split.artistUpdateExecutableAt(), 0);
        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert(bytes('no pending update'));
        split.executeArtistUpdate();
    }

    /// The load-bearing property: rotating the address preserves the split and
    /// hands accrued-but-unclaimed 5% to the new address, with no double-pay.
    function test_Rotation_AccountingContinuity() public {
        // 1 ETH in; artist claims their 0.05 at the old address
        _fund(1 ether);
        vm.prank(artistP);
        split.release(artistP);
        assertEq(artistP.balance, 0.05 ether);

        // rotate to a new address
        address payable newArtist = payable(makeAddr("newArtist"));
        vm.prank(admin);
        split.proposeArtistUpdate(newArtist);
        vm.warp(block.timestamp + 48 hours);
        split.executeArtistUpdate();

        // old address is owed nothing further; it cannot claim again
        vm.expectRevert(bytes('account has no shares'));
        split.release(artistP);

        // second 1 ETH in: new address is owed exactly its 0.05, NOT 0.10
        _fund(1 ether);
        assertEq(split.releasable(newArtist), 0.05 ether, "no double-pay after rotation");
        vm.prank(newArtist);
        split.release(newArtist);
        assertEq(newArtist.balance, 0.05 ether);

        // company still whole across the rotation
        split.release(company);
        assertEq(company.balance, 1.8 ether);
        vm.prank(designerP);
        split.release(designerP);
        assertEq(designerP.balance, 0.1 ether);
        assertLe(address(split).balance, 1);
    }

    /// 5% that accrued while the old key was live but was never claimed must be
    /// recoverable by the new address — the key-loss recovery case.
    function test_Rotation_UnclaimedAccrualFollowsRole() public {
        _fund(1 ether); // artist never claims their 0.05 (lost key)
        address payable newArtist = payable(makeAddr("newArtist"));
        vm.prank(admin);
        split.proposeArtistUpdate(newArtist);
        vm.warp(block.timestamp + 48 hours);
        split.executeArtistUpdate();

        assertEq(split.releasable(newArtist), 0.05 ether, "stranded 5% follows the role");
        vm.prank(newArtist);
        split.release(newArtist);
        assertEq(newArtist.balance, 0.05 ether);
    }

    /// F2 (audit) — ERC-20 payout continuity across an artist rotation:
    /// the pre-rotation unclaimed 5% follows the role, the old address is owed
    /// nothing, and there is no double-pay on later funding.
    function test_Rotation_Erc20AccountingContinuity() public {
        ERC20Mock mock = new ERC20Mock();
        mock.mint(address(split), 1000 ether); // artist's 5% (50) accrues, never claimed

        address payable newArtist = payable(makeAddr("newArtistErc20"));
        vm.prank(admin);
        split.proposeArtistUpdate(newArtist);
        vm.warp(block.timestamp + 48 hours);
        split.executeArtistUpdate();

        // stranded 5% follows the role to the new address (key-loss recovery)
        assertEq(split.releasable(IERC20(address(mock)), newArtist), 50 ether, "stranded ERC20 5% follows role");
        // old address has no role now — cannot claim
        vm.expectRevert(bytes('account has no shares'));
        split.release(IERC20(address(mock)), artistP);

        vm.prank(newArtist);
        split.release(IERC20(address(mock)), newArtist);
        assertEq(mock.balanceOf(newArtist), 50 ether);

        // second funding: new address owed exactly 5%, NOT 10%
        mock.mint(address(split), 1000 ether);
        assertEq(split.releasable(IERC20(address(mock)), newArtist), 50 ether, "no ERC20 double-pay after rotation");
        vm.prank(newArtist);
        split.release(IERC20(address(mock)), newArtist);
        assertEq(mock.balanceOf(newArtist), 100 ether);

        // company whole across the rotation (90% of 2000)
        split.release(IERC20(address(mock)), company);
        assertEq(mock.balanceOf(company), 1800 ether);
    }

    // -------------------------------------- audit Rev 12 (H-02, H-01, L-01)

    /// H-02: a rotatable payee's funds can ONLY be released by that payee. A
    /// third party can never push the artist's or designer's accrued share to
    /// their address — no matter who is trying or when. This is what makes a
    /// key-loss rotation safe: accrued funds sit in the pot until the payee (or
    /// its successor after rotation) claims. Company stays permissionless.
    function test_H02_OnlyPayeeMayReleaseRotatableRole() public {
        _fund(1 ether); // artist + designer each accrue 0.05, unclaimed

        // no third party may push the artist's or designer's share, ETH...
        vm.prank(makeAddr("griefer"));
        vm.expectRevert(bytes('only the payee may release'));
        split.release(artistP);
        vm.prank(makeAddr("griefer"));
        vm.expectRevert(bytes('only the payee may release'));
        split.release(designerP);

        // ...or ERC-20
        ERC20Mock mock = new ERC20Mock();
        mock.mint(address(split), 1000 ether);
        vm.prank(makeAddr("griefer"));
        vm.expectRevert(bytes('only the payee may release'));
        split.release(IERC20(address(mock)), artistP);

        // company is immutable, so its release stays permissionless
        vm.prank(makeAddr("anyone"));
        split.release(company);
        assertEq(company.balance, 0.9 ether);

        // the payees themselves can always claim
        vm.prank(artistP);
        split.release(artistP);
        assertEq(artistP.balance, 0.05 ether);
        vm.prank(designerP);
        split.release(designerP);
        assertEq(designerP.balance, 0.05 ether);
    }

    /// H-02 (the escalation over Rev 11): the guard bites BEFORE any proposal
    /// exists, so the front-run window that a rotation-time freeze left open is
    /// closed. A griefer cannot strand the accrued 5% at a lost address by
    /// racing the proposal; the successor recovers the full accrual.
    function test_H02_ThirdPartyReleaseBlockedBeforeAndDuringRotation() public {
        _fund(1 ether); // 0.05 accrues to a lost artist key, unclaimed
        address payable lost = artistP;
        address payable newA = payable(makeAddr("newArtist"));

        // BEFORE any proposal: a griefer still cannot push to the lost address
        vm.prank(makeAddr("griefer"));
        vm.expectRevert(bytes('only the payee may release'));
        split.release(lost);

        // company + designer keep flowing regardless
        split.release(company);
        assertEq(company.balance, 0.9 ether);
        vm.prank(designerP);
        split.release(designerP);
        assertEq(designerP.balance, 0.05 ether);

        // rotate; DURING the pending window the griefer is still blocked
        vm.prank(admin);
        split.proposeArtistUpdate(newA);
        vm.prank(makeAddr("griefer"));
        vm.expectRevert(bytes('only the payee may release'));
        split.release(lost);

        // after execution the successor claims the full accrued 5%
        vm.warp(block.timestamp + 48 hours);
        split.executeArtistUpdate();
        assertEq(split.releasable(newA), 0.05 ether, "H-02: stranded 5% follows the role");
        vm.prank(newA);
        split.release(newA);
        assertEq(newA.balance, 0.05 ether);
    }

    /// H-02: the designer role mirrors the artist guard.
    function test_H02_DesignerThirdPartyReleaseBlocked() public {
        _fund(1 ether);
        vm.prank(admin);
        split.proposeDesignerUpdate(makeAddr("newDesigner"));
        vm.prank(makeAddr("griefer"));
        vm.expectRevert(bytes('only the payee may release'));
        split.release(designerP);
        // artist unaffected: it can still claim its own share
        vm.prank(artistP);
        split.release(artistP);
        assertEq(artistP.balance, 0.05 ether);
    }

    /// L-01: the splitter's own address is rejected as any payee.
    function test_L01_SelfPayeeRejected() public {
        // constructor guards
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(bytes('company is splitter'));
        new CypherPunksSplitter(payable(predicted), artistP, designerP, admin);
        // rotation guards
        vm.startPrank(admin);
        vm.expectRevert(bytes('new artist is splitter'));
        split.proposeArtistUpdate(address(split));
        vm.expectRevert(bytes('new designer is splitter'));
        split.proposeDesignerUpdate(address(split));
        vm.stopPrank();
    }

    /// K-01 (Kimi audit): admin and payee roles stay separate across rotations,
    /// not just at construction — neither payee may be rotated onto the admin.
    function test_K01_CannotRotatePayeeOntoAdmin() public {
        vm.startPrank(admin);
        vm.expectRevert(bytes('new artist is admin'));
        split.proposeArtistUpdate(admin);
        vm.expectRevert(bytes('new designer is admin'));
        split.proposeDesignerUpdate(admin);
        vm.stopPrank();
    }

    // ---------------------------------------------- designer rotation (48h)

    function test_DesignerRotation_MirrorsArtist() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(bytes('not payee admin'));
        split.proposeDesignerUpdate(makeAddr("newDesigner"));

        vm.startPrank(admin);
        vm.expectRevert(bytes('new designer zero'));
        split.proposeDesignerUpdate(address(0));
        vm.expectRevert(bytes('new designer is company'));
        split.proposeDesignerUpdate(company);
        vm.expectRevert(bytes('new designer is artist'));
        split.proposeDesignerUpdate(artistP);
        vm.expectRevert(bytes('new designer unchanged'));
        split.proposeDesignerUpdate(designerP);

        address newDesigner = makeAddr("newDesigner");
        split.proposeDesignerUpdate(newDesigner);
        vm.stopPrank();
        assertEq(split.pendingDesigner(), newDesigner);
        assertEq(split.designerUpdateExecutableAt(), block.timestamp + 48 hours);

        vm.prank(makeAddr("anyone"));
        vm.expectRevert(bytes('timelock not elapsed'));
        split.executeDesignerUpdate();

        vm.warp(block.timestamp + 48 hours);
        vm.prank(makeAddr("anyone"));
        split.executeDesignerUpdate();
        assertEq(split.designer(), newDesigner);
        assertEq(split.shares(newDesigner), 5, "new designer inherits 5%");
        assertEq(split.shares(designerP), 0, "old designer loses the role");
    }

    /// Accrued-but-unclaimed designer 5% follows the role across a rotation
    /// (key-loss recovery, mirror of the artist property).
    function test_DesignerRotation_AccountingContinuity() public {
        _fund(1 ether); // designer never claims (lost key)
        address payable newDesigner = payable(makeAddr("newDesigner"));
        vm.prank(admin);
        split.proposeDesignerUpdate(newDesigner);
        vm.warp(block.timestamp + 48 hours);
        split.executeDesignerUpdate();

        assertEq(split.releasable(newDesigner), 0.05 ether, "stranded 5% follows the role");
        vm.expectRevert(bytes('account has no shares'));
        split.release(designerP);

        _fund(1 ether);
        assertEq(split.releasable(newDesigner), 0.1 ether, "no double-pay after rotation");
        vm.prank(newDesigner);
        split.release(newDesigner);
        assertEq(newDesigner.balance, 0.1 ether);
    }

    /// Cross-payee race: a matured artist proposal must not execute onto the
    /// address the designer rotated to while it was pending (and vice versa).
    function test_Rotation_CrossPayeeCollisionBlocked() public {
        address clash = makeAddr("clash");
        vm.prank(admin);
        split.proposeArtistUpdate(clash);
        vm.prank(admin);
        split.proposeDesignerUpdate(clash);
        vm.warp(block.timestamp + 48 hours);

        // whichever executes first wins the address...
        split.executeDesignerUpdate();
        assertEq(split.designer(), clash);
        // ...and the other matured proposal is now blocked
        vm.expectRevert(bytes('new artist is designer'));
        split.executeArtistUpdate();
    }
}

/// End-to-end: auction proceeds land in the real splitter through the
/// verbatim transfer path, then release pays 90/5/5 (I10 shape).
contract SplitterEndToEndTest is Fixture {
    function test_SettlementProceedsThroughSplitter() public {
        bidAs(makeAddr("winner"), 1 ether);
        warpPastEnd();
        ah.settleCurrentAndCreateNewAuction();

        assertEq(address(splitter).balance, 1 ether, "hammer price at splitter");

        vm.prank(makeAddr("anyone"));
        splitter.release(payable(companyPayee));
        vm.prank(artistPayee);
        splitter.release(payable(artistPayee));
        vm.prank(designerPayee);
        splitter.release(payable(designerPayee));

        assertEq(companyPayee.balance, 0.9 ether);
        assertEq(artistPayee.balance, 0.05 ether);
        assertEq(designerPayee.balance, 0.05 ether);
    }

}
