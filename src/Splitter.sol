// SPDX-License-Identifier: GPL-3.0

/// @title The CypherPunks payment splitter

// LICENSE
// Splitter.sol follows the OpenZeppelin PaymentSplitter pattern (vendored
// unmodified in reference/PaymentSplitter.sol, from OZ v4.9.6 — the contract
// was removed in OZ v5). Pull-payment share accounting kept; everything
// mutable stripped (doc §02 row 4): shares are fixed forever.
//
// CypherPunks deltas from the OZ reference:
//   KEEP (pattern): pull-payment accounting — totalReceived-based releasable
//     math for ETH and ERC-20, released counters, permissionless release.
//   STRIP: constructor-supplied payee arrays and _addPayee (any payee-set
//     mutation path); Context base; payee enumeration by index.
//   ADD: fixed 90/5/5 company/artist/designer shares as compile-time
//     constants (doc §01 PRIMARY_SPLIT, "Hardcoded in splitter"); an immutable
//     company payee; *rotatable* artist and designer payees, each behind a 48h
//     timelock held by an immutable payeeAdmin (Safe) — recovery if either
//     individual loses their key (artist ruled 2026-07-16, designer added
//     2026-07-25). SHARES stay fixed forever; only the individual *addresses*
//     can change, and only after the delay.
//
// Accounting note (role-keyed, not address-keyed): released counters are
// tracked per ROLE (company / artist / designer), not per address. Rotating an
// individual payee's address therefore preserves the split exactly — the new
// address inherits that role's released counter (no double-pay), and any 5%
// that accrued but was never claimed by a lost key stays claimable by the new
// address. This is the property that makes key-loss recovery safe.

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CypherPunksSplitter {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------- §01 constants

    /// @notice PRIMARY_SPLIT: 90 / 5 / 5 company / artist / designer.
    ///         Hardcoded; the same split applies to everything the splitter
    ///         receives (doc §02 row 4: shares constant forever). Secondary
    ///         sale royalties were removed at Rev 3 — this contract only ever
    ///         sees primary proceeds.
    uint256 public constant COMPANY_SHARES = 90;
    uint256 public constant ARTIST_SHARES = 5;
    uint256 public constant DESIGNER_SHARES = 5;
    uint256 public constant TOTAL_SHARES = 100;

    /// @notice Delay an individual-payee rotation sits behind once proposed.
    ///         Despite the name, this governs BOTH the artist and the designer
    ///         rotation timelocks (the two rotatable 5% roles share one delay).
    uint256 public constant ARTIST_UPDATE_DELAY = 48 hours;

    /// @dev Role ids for the role-keyed accounting (0 = not a payee).
    uint256 private constant ROLE_COMPANY = 1;
    uint256 private constant ROLE_ARTIST = 2;
    uint256 private constant ROLE_DESIGNER = 3;

    // ----------------------------------------------------------- immutables

    /// @notice The 90% payee. Immutable — recover a lost key by rotating the
    ///         signers of this Safe, never the address.
    address payable public immutable company;

    /// @notice The Safe permitted to propose/cancel an artist- or designer-
    ///         address rotation (execution is permissionless once the timelock
    ///         matures).
    address public immutable payeeAdmin;

    // -------------------------------------------------------------- storage

    /// @notice The artist 5% payee. Rotatable via the timelock below.
    address payable public artist;

    /// @notice The designer 5% payee. Rotatable via the timelock below.
    address payable public designer;

    /// @notice Proposed next artist address; zero when none is pending.
    address public pendingArtist;
    /// @notice When the pending artist rotation becomes executable; zero = none.
    uint256 public artistUpdateExecutableAt;

    /// @notice Proposed next designer address; zero when none is pending.
    address public pendingDesigner;
    /// @notice When the pending designer rotation becomes executable; zero = none.
    uint256 public designerUpdateExecutableAt;

    /// @dev Role-keyed released counters (role id → amount). Address-agnostic
    ///      so an artist rotation never disturbs the accounting.
    uint256 public totalReleased;
    mapping(uint256 => uint256) public releasedByRole;

    mapping(IERC20 => uint256) public erc20TotalReleased;
    mapping(IERC20 => mapping(uint256 => uint256)) public erc20ReleasedByRole;

    // --------------------------------------------------------------- events

    event PaymentReceived(address from, uint256 amount);
    event PaymentReleased(address to, uint256 amount);
    event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
    event ArtistUpdateProposed(address indexed newArtist, uint256 executableAt);
    event ArtistUpdateCancelled();
    event ArtistUpdated(address indexed oldArtist, address indexed newArtist);
    event DesignerUpdateProposed(address indexed newDesigner, uint256 executableAt);
    event DesignerUpdateCancelled();
    event DesignerUpdated(address indexed oldDesigner, address indexed newDesigner);

    // ---------------------------------------------------------- constructor

    constructor(
        address payable company_,
        address payable artist_,
        address payable designer_,
        address payeeAdmin_
    ) {
        require(company_ != address(0), 'company is zero');
        // reject the splitter's own address anywhere: a self-payee's release()
        // sends ETH to this contract, leaving the balance unchanged while
        // totalReleased grows — inflating totalReceived (audit L-01, Rev 11)
        require(company_ != address(this), 'company is splitter');
        require(artist_ != address(this), 'artist is splitter');
        require(designer_ != address(this), 'designer is splitter');
        require(payeeAdmin_ != address(this), 'admin is splitter');
        require(artist_ != address(0), 'artist is zero');
        require(designer_ != address(0), 'designer is zero');
        require(payeeAdmin_ != address(0), 'admin is zero');
        require(company_ != artist_, 'payees identical');
        require(company_ != designer_, 'payees identical');
        require(artist_ != designer_, 'payees identical');
        // The admin rotates the individual payees; it must not BE one of them.
        require(payeeAdmin_ != artist_, 'admin is artist');
        require(payeeAdmin_ != designer_, 'admin is designer');
        // NOTE (audit F4): payeeAdmin MAY equal the company. The project runs a
        // single 3-of-5 team Safe as both company and payeeAdmin (ruled
        // 2026-07-20), so the team can rotate the *artist* and *designer* payees
        // behind the 48h public timelock — a disclosed, key-loss-recovery power,
        // not an unprivileged path. The company's immutable 90% and all other
        // funds are untouchable by this role; only the artist's and designer's
        // 5% addresses are rotatable.
        company = company_;
        artist = artist_;
        designer = designer_;
        payeeAdmin = payeeAdmin_;
    }

    /// @dev Kept minimal: the auction house pushes proceeds with a 30k-gas
    ///      stipend; this must always fit within it.
    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

    // ------------------------------------------------------ artist rotation

    /// @notice Propose a new artist payee. Admin only; takes effect only after
    ///         ARTIST_UPDATE_DELAY via executeArtistUpdate(). Re-proposing
    ///         overwrites any pending proposal and restarts the timer.
    function proposeArtistUpdate(address newArtist) external {
        require(msg.sender == payeeAdmin, 'not payee admin');
        require(newArtist != address(0), 'new artist zero');
        require(newArtist != company, 'new artist is company');
        require(newArtist != designer, 'new artist is designer');
        require(newArtist != address(this), 'new artist is splitter');
        // keep admin and payee roles separate across rotations, not just at
        // construction (audit K-01). Moot when payeeAdmin == company (our
        // genesis config), enforced unconditionally for any deployment.
        require(newArtist != payeeAdmin, 'new artist is admin');
        require(newArtist != artist, 'new artist unchanged');
        pendingArtist = newArtist;
        artistUpdateExecutableAt = block.timestamp + ARTIST_UPDATE_DELAY;
        emit ArtistUpdateProposed(newArtist, artistUpdateExecutableAt);
    }

    /// @notice Abort a pending artist rotation. Admin only.
    function cancelArtistUpdate() external {
        require(msg.sender == payeeAdmin, 'not payee admin');
        require(artistUpdateExecutableAt != 0, 'no pending update');
        pendingArtist = address(0);
        artistUpdateExecutableAt = 0;
        emit ArtistUpdateCancelled();
    }

    /// @notice Execute a matured artist rotation. Permissionless — the timelock
    ///         is the gate, not the caller (mirrors AuctionHouse.unpause). The
    ///         artist role's released counter is untouched, so the split and
    ///         all accrued-but-unclaimed 5% carry over to the new address.
    function executeArtistUpdate() external {
        require(artistUpdateExecutableAt != 0, 'no pending update');
        require(block.timestamp >= artistUpdateExecutableAt, 'timelock not elapsed');
        // Re-check company (immutable) and designer (may have rotated to the
        // pending address while this proposal matured).
        require(pendingArtist != company, 'new artist is company');
        require(pendingArtist != designer, 'new artist is designer');
        address old = artist;
        artist = payable(pendingArtist);
        pendingArtist = address(0);
        artistUpdateExecutableAt = 0;
        emit ArtistUpdated(old, artist);
    }

    // ---------------------------------------------------- designer rotation

    /// @notice Propose a new designer payee. Admin only; takes effect only
    ///         after ARTIST_UPDATE_DELAY via executeDesignerUpdate().
    ///         Re-proposing overwrites any pending proposal and restarts the
    ///         timer. Mirrors the artist rotation exactly.
    function proposeDesignerUpdate(address newDesigner) external {
        require(msg.sender == payeeAdmin, 'not payee admin');
        require(newDesigner != address(0), 'new designer zero');
        require(newDesigner != company, 'new designer is company');
        require(newDesigner != artist, 'new designer is artist');
        require(newDesigner != address(this), 'new designer is splitter');
        require(newDesigner != payeeAdmin, 'new designer is admin'); // audit K-01
        require(newDesigner != designer, 'new designer unchanged');
        pendingDesigner = newDesigner;
        designerUpdateExecutableAt = block.timestamp + ARTIST_UPDATE_DELAY;
        emit DesignerUpdateProposed(newDesigner, designerUpdateExecutableAt);
    }

    /// @notice Abort a pending designer rotation. Admin only.
    function cancelDesignerUpdate() external {
        require(msg.sender == payeeAdmin, 'not payee admin');
        require(designerUpdateExecutableAt != 0, 'no pending update');
        pendingDesigner = address(0);
        designerUpdateExecutableAt = 0;
        emit DesignerUpdateCancelled();
    }

    /// @notice Execute a matured designer rotation. Permissionless — the
    ///         timelock is the gate, not the caller. The designer role's
    ///         released counter is untouched, so the split and all accrued
    ///         but unclaimed 5% carry over to the new address.
    function executeDesignerUpdate() external {
        require(designerUpdateExecutableAt != 0, 'no pending update');
        require(block.timestamp >= designerUpdateExecutableAt, 'timelock not elapsed');
        // Re-check company (immutable) and artist (may have rotated to the
        // pending address while this proposal matured).
        require(pendingDesigner != company, 'new designer is company');
        require(pendingDesigner != artist, 'new designer is artist');
        address old = designer;
        designer = payable(pendingDesigner);
        pendingDesigner = address(0);
        designerUpdateExecutableAt = 0;
        emit DesignerUpdated(old, designer);
    }

    // -------------------------------------------------------------- lookups

    /// @notice Role id for `account` under the current payee set (0 = none).
    function roleOf(address account) public view returns (uint256) {
        if (account == company) return ROLE_COMPANY;
        if (account == artist) return ROLE_ARTIST;
        if (account == designer) return ROLE_DESIGNER;
        return 0;
    }

    function shares(address account) public view returns (uint256) {
        uint256 role = roleOf(account);
        if (role == ROLE_COMPANY) return COMPANY_SHARES;
        if (role == ROLE_ARTIST) return ARTIST_SHARES;
        if (role == ROLE_DESIGNER) return DESIGNER_SHARES;
        return 0;
    }

    /// @notice ETH still owed to `account` under the fixed split.
    function releasable(address account) public view returns (uint256) {
        uint256 role = roleOf(account);
        if (role == 0) return 0;
        uint256 totalReceived = address(this).balance + totalReleased;
        return _pending(role, totalReceived, releasedByRole[role]);
    }

    /// @notice `token` amount still owed to `account` under the fixed split.
    function releasable(IERC20 token, address account) public view returns (uint256) {
        uint256 role = roleOf(account);
        if (role == 0) return 0;
        uint256 totalReceived = token.balanceOf(address(this)) + erc20TotalReleased[token];
        return _pending(role, totalReceived, erc20ReleasedByRole[token][role]);
    }

    // -------------------------------------------------------------- release

    /// @dev A rotatable payee (artist, designer) may only release its OWN funds:
    ///      `msg.sender` must equal the payee address. A lost key can never sign,
    ///      so no third party can push a role's accrued funds to a lost or
    ///      about-to-be-rotated address — role-keyed accounting would otherwise
    ///      record it paid and the successor could never reclaim it. This closes
    ///      the front-run window that a rotation-time freeze left open before the
    ///      proposal lands (audit H-01, H-02, Rev 12). The company payee is
    ///      immutable (only its Safe signers rotate, never its address) so its
    ///      release stays permissionless.
    function _requireSelfIfRotatable(uint256 role, address account) private view {
        if (role != ROLE_COMPANY) require(msg.sender == account, 'only the payee may release');
    }

    /// @notice Release owed ETH to a payee. Company release is permissionless;
    ///         a rotatable payee must call for itself. Funds only ever go to the
    ///         current payee address.
    function release(address payable account) external {
        uint256 role = roleOf(account);
        require(role != 0, 'account has no shares');
        _requireSelfIfRotatable(role, account);
        uint256 payment = releasable(account);
        require(payment != 0, 'account is not due payment');

        releasedByRole[role] += payment;
        totalReleased += payment;

        emit PaymentReleased(account, payment);
        (bool success,) = account.call{value: payment}("");
        require(success, 'payment failed');
    }

    /// @notice Release owed `token` to a payee. Company release is
    ///         permissionless; a rotatable payee must call for itself.
    function release(IERC20 token, address account) external {
        uint256 role = roleOf(account);
        require(role != 0, 'account has no shares');
        _requireSelfIfRotatable(role, account);
        uint256 payment = releasable(token, account);
        require(payment != 0, 'account is not due payment');

        erc20ReleasedByRole[token][role] += payment;
        erc20TotalReleased[token] += payment;

        emit ERC20PaymentReleased(token, account, payment);
        token.safeTransfer(account, payment);
    }

    // ------------------------------------------------------------ internals

    /// @dev OZ PaymentSplitter pendingPayment math, keyed by role.
    function _pending(uint256 role, uint256 totalReceived, uint256 alreadyReleased)
        private
        pure
        returns (uint256)
    {
        uint256 roleShares = role == ROLE_COMPANY
            ? COMPANY_SHARES
            : (role == ROLE_ARTIST ? ARTIST_SHARES : DESIGNER_SHARES);
        return (totalReceived * roleShares) / TOTAL_SHARES - alreadyReleased;
    }
}
