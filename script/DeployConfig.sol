// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {CypherPunksToken} from "../src/Token.sol";
import {CypherPunksAuctionHouse} from "../src/AuctionHouse.sol";
import {CypherPunksSplitter} from "../src/Splitter.sol";
import {IDescriptor} from "../src/interfaces/IDescriptor.sol";

/// All deploy-time inputs, surfaced as one explicit struct (doc §11 open
/// inputs). No value is invented — every field is caller-supplied.
struct DeployConfig {
    address treasury; // company primary payee (Safe) + 90% splitter share
    address artist; // artist primary payee (5% splitter share) — payments ONLY
    address designer; // designer primary payee (5% splitter share) — payments ONLY
    address payeeAdmin; // Safe that may rotate the artist/designer payees (48h timelock)
    // Recipient of BOTH genesis tails, token IDs 9,801–10,000 (ruled
    // 2026-07-16): the 100 artists-allocation pieces are grants for future
    // etch'd artists — NOT the splitter artist — so both tails mint to one
    // project Safe and are distributed manually post-genesis.
    address reserveTreasury;
    address pauseGuardian; // 3-of-5 Safe (doc §01)
    address vrfCoordinator; // Chainlink VRF v2.5 coordinator (mainnet)
    bytes32 vrfKeyHash; // VRF gas-lane key hash
    uint256 vrfSubId; // VRF v2.5 subscription id
    // Descriptor is immutable in the Token constructor (no setter). Address
    // zero → placeholder tokenURI until Phase 8's Descriptor is deployed
    // FIRST and its address passed here. See DeployLib notes / Phase 7 flag.
    address descriptor;
}

/// Shared deploy + post-deploy verification, used by both the production
/// deploy script and the seed-ceremony rehearsal so the two can never drift.
library DeployLib {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct Deployment {
        CypherPunksToken token;
        CypherPunksAuctionHouse auctionHouse;
        CypherPunksSplitter splitter;
    }

    // ------------------------------------------------------------- validate

    /// Reverts on any zero or obviously-wrong input. `deployer` is the EOA
    /// running the script; the guardian and treasuries must not be it.
    /// Canonical Chainlink VRF v2.5 coordinator on Ethereum mainnet. A wrong
    /// coordinator deploys fine and then bricks genesis forever (immutable, the
    /// seed request goes nowhere) — so a mainnet deploy refuses anything else
    /// (audit Finding 2).
    address internal constant MAINNET_VRF_COORDINATOR = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;

    function validate(DeployConfig memory c, address deployer) internal view {
        require(c.treasury != address(0), "config: treasury zero");
        require(c.artist != address(0), "config: artist zero");
        require(c.designer != address(0), "config: designer zero");
        require(c.payeeAdmin != address(0), "config: payeeAdmin zero");
        require(c.reserveTreasury != address(0), "config: reserveTreasury zero");
        require(c.pauseGuardian != address(0), "config: pauseGuardian zero");
        require(c.vrfCoordinator != address(0), "config: vrfCoordinator zero");
        // mainnet: only the canonical coordinator can fulfill the one seed request
        if (block.chainid == 1) {
            require(
                c.vrfCoordinator == MAINNET_VRF_COORDINATOR,
                "config: not the canonical mainnet VRF coordinator"
            );
        }
        require(c.vrfSubId != 0, "config: vrfSubId zero");
        // The gas-lane key hash is as load-bearing as the coordinator: a zero or
        // unregistered lane deploys fine, then reverts requestSeed at the
        // coordinator on genesis morning. Guard non-zero (the lane itself is a
        // legitimate per-deploy choice, so it is not pinned) — audit D-01.
        require(c.vrfKeyHash != bytes32(0), "config: vrfKeyHash zero");

        // descriptor is immutable with no setter (doc §02 "Deploy ordering"):
        // a zero descriptor is a fatal production error — the art must be
        // final and the Descriptor deployed first. The address(0) placeholder
        // path in the Token is test-only.
        require(c.descriptor != address(0), "config: descriptor zero (deploy Descriptor first)");

        // guardian must be a Safe, never the deploying EOA (doc §01)
        require(c.pauseGuardian != deployer, "config: guardian == deployer EOA");
        require(c.treasury != deployer, "config: treasury == deployer EOA");
        require(c.artist != deployer, "config: artist == deployer EOA");
        require(c.designer != deployer, "config: designer == deployer EOA");
        require(c.reserveTreasury != deployer, "config: reserve == deployer EOA");

        // payees must be distinct (splitter forbids identical payees)
        require(c.treasury != c.artist, "config: treasury == artist");
        require(c.treasury != c.designer, "config: treasury == designer");
        require(c.artist != c.designer, "config: artist == designer");
        // the payee admin rotates the artist/designer addresses; it must not
        // be either of them, nor the deploying EOA (it is the company Safe)
        require(c.payeeAdmin != c.artist, "config: payeeAdmin == artist");
        require(c.payeeAdmin != c.designer, "config: payeeAdmin == designer");
        require(c.payeeAdmin != deployer, "config: payeeAdmin == deployer EOA");
        // the artists allocation is a project grants pool, never an individual
        // payee wallet — guards the exact coupling this field was split from
        require(c.reserveTreasury != c.artist, "config: reserve == artist payee");
        require(c.reserveTreasury != c.designer, "config: reserve == designer payee");
    }

    // --------------------------------------------------------------- deploy

    /// Deploys in the §05 lock order. Splitter first (no deps); Token next
    /// against the PRECOMPUTED AuctionHouse address (circular immutables);
    /// AuctionHouse last. All algorithm code and constants are immutable at
    /// deploy — the VRF request can only be made afterwards.
    function deploy(DeployConfig memory c, address deployer)
        internal
        returns (Deployment memory d)
    {
        validate(c, deployer);

        d.splitter =
            new CypherPunksSplitter(
                payable(c.treasury), payable(c.artist), payable(c.designer), c.payeeAdmin
            );

        // predict the AuctionHouse address: it is the deployer's next-next
        // CREATE (Token is next, AuctionHouse the one after).
        uint64 nonce = vm.getNonce(deployer);
        address predictedAH = vm.computeCreateAddress(deployer, nonce + 1);

        d.token = new CypherPunksToken(
            predictedAH,
            c.reserveTreasury, // artists-allocation tail (9,801–9,900)
            c.reserveTreasury, // team tail (9,901–10,000)
            c.vrfCoordinator,
            c.vrfKeyHash,
            c.vrfSubId,
            IDescriptor(c.descriptor)
        );

        d.auctionHouse = new CypherPunksAuctionHouse(d.token, address(d.splitter), c.pauseGuardian);
        require(address(d.auctionHouse) == predictedAH, "deploy: AH address prediction drifted");
    }

    // ---------------------------------------------- post-deploy assertions

    /// Deploy-time twin of I14/I11: re-verify onchain that every §01 constant
    /// matches the doc, that no owner() exists, and that the wiring graph is
    /// exactly token↔auctionHouse↔splitter. Reverts loudly on any mismatch.
    function verify(Deployment memory d, DeployConfig memory c) internal view {
        CypherPunksToken t = d.token;
        CypherPunksAuctionHouse a = d.auctionHouse;
        CypherPunksSplitter s = d.splitter;

        // --- §01 constants (AuctionHouse) ---
        require(a.DURATION() == 24 hours, "verify: DURATION");
        require(a.TIME_BUFFER() == 10 minutes, "verify: TIME_BUFFER");
        require(a.MIN_BID_INCREMENT_PERCENTAGE() == 2, "verify: MIN_INCREMENT");
        require(a.MIN_BID_STEP() == 0.001 ether, "verify: MIN_BID_STEP");
        require(a.RESERVE_PRICE() == 0, "verify: RESERVE_PRICE");
        require(a.UNPAUSE_DELAY() == 48 hours, "verify: UNPAUSE_DELAY");
        require(a.WETH() == WETH, "verify: WETH");

        // --- §01 constants (Token) ---
        require(t.TOTAL_SUPPLY() == 10_000, "verify: TOTAL_SUPPLY");
        require(t.PUBLIC_COUNT() == 9_800, "verify: PUBLIC_COUNT");
        require(t.ARTIST_COUNT() == 100 && t.TEAM_COUNT() == 100, "verify: reserved counts");
        require(t.ARTIST_ID_START() == 9_801 && t.TEAM_ID_START() == 9_901, "verify: id starts");
        require(t.RE_REQUEST_TIMEOUT() == 7 days, "verify: RE_REQUEST_TIMEOUT");
        require(t.VRF_CALLBACK_GAS_LIMIT() == 100_000, "verify: VRF_CALLBACK_GAS_LIMIT");
        require(t.VRF_REQUEST_CONFIRMATIONS() == 6, "verify: VRF_REQUEST_CONFIRMATIONS");
        require(
            keccak256(bytes(t.name())) == keccak256("CypherPunks")
                && keccak256(bytes(t.symbol())) == keccak256("PUNK"),
            "verify: name/symbol"
        );

        // --- zero secondary royalties (Rev 3): no ERC-2981 ---
        require(!t.supportsInterface(0x2a55205a), "verify: ERC-2981 present");
        require(
            t.supportsInterface(0x80ac58cd) && t.supportsInterface(0x5b5e139f)
                && t.supportsInterface(0x01ffc9a7),
            "verify: 721/metadata/165 surface"
        );

        // --- wiring graph exactly as specified ---
        require(t.auctionHouse() == address(a), "verify: token.auctionHouse");
        require(a.token() == t, "verify: ah.token");
        require(a.splitter() == address(s), "verify: ah.splitter");
        require(a.pauseGuardian() == c.pauseGuardian, "verify: ah.guardian");
        require(t.artistTreasury() == c.reserveTreasury, "verify: token.artistTail");
        require(t.teamTreasury() == c.reserveTreasury, "verify: token.teamTail");
        require(t.vrfCoordinator() == c.vrfCoordinator, "verify: token.vrfCoordinator");
        require(address(t.descriptor()) == c.descriptor, "verify: token.descriptor");

        // --- splitter shares fixed 90/5/5 to the right payees ---
        require(s.shares(c.treasury) == 90, "verify: company share");
        require(s.shares(c.artist) == 5, "verify: artist share");
        require(s.shares(c.designer) == 5, "verify: designer share");
        // --- payee rotation wired: admin set, 48h delay, none pending ---
        require(s.payeeAdmin() == c.payeeAdmin, "verify: payeeAdmin");
        require(s.artist() == c.artist, "verify: splitter artist");
        require(s.designer() == c.designer, "verify: splitter designer");
        require(s.company() == c.treasury, "verify: splitter company");
        require(s.ARTIST_UPDATE_DELAY() == 48 hours, "verify: artist delay");
        require(s.artistUpdateExecutableAt() == 0, "verify: rotation pending");
        require(s.designerUpdateExecutableAt() == 0, "verify: designer rotation pending");

        // --- no owner() anywhere (privilege surface, I11) ---
        require(!_hasOwner(address(t)), "verify: token has owner()");
        require(!_hasOwner(address(a)), "verify: ah has owner()");
        require(!_hasOwner(address(s)), "verify: splitter has owner()");

        // --- pre-genesis: no seed, no auction, walk not started ---
        require(!t.seedFulfilled() && t.seed() == 0, "verify: seed already set");
        require(t.publicMinted() == 0, "verify: tokens already minted");
        require(a.auction().startTime == 0, "verify: auction already live");
    }

    function _hasOwner(address target) private view returns (bool) {
        (bool ok,) = target.staticcall(abi.encodeWithSignature("owner()"));
        return ok;
    }
}
