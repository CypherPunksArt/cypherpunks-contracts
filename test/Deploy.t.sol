// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployConfig, DeployLib} from "../script/DeployConfig.sol";
import {VRFCoordinatorV2PlusMock} from "./helpers/VRFCoordinatorV2PlusMock.sol";
import {WETHMock} from "./helpers/Fixture.sol";
import {DescriptorStub} from "./helpers/DescriptorStub.sol";

/// External wrapper so expectRevert sees validate at a lower call depth
/// (it is an internal library function).
contract ValidateHarness {
    function validate(DeployConfig calldata c, address deployer) external view {
        DeployLib.validate(c, deployer);
    }
}

/// Covers the deploy infrastructure: config validation rejects bad inputs,
/// deploy wires the graph in §05 lock order, and the post-deploy assertion
/// block (DeployLib.verify) passes on a good deployment.
contract DeployTest is Test {
    address internal coord;
    address internal descriptor;
    address internal deployer = makeAddr("deployer");
    ValidateHarness internal harness;

    function setUp() public {
        WETHMock impl = new WETHMock();
        vm.etch(DeployLib.WETH, address(impl).code);
        coord = address(new VRFCoordinatorV2PlusMock());
        descriptor = address(new DescriptorStub()); // real Descriptor is Phase 8
        harness = new ValidateHarness();
    }

    function _goodConfig() internal view returns (DeployConfig memory c) {
        c = DeployConfig({
            treasury: address(0xA11CE),
            artist: address(0xB0B),
            designer: address(0xD151),
            payeeAdmin: address(0xADA11),
            reserveTreasury: address(0xC0FFEE),
            pauseGuardian: address(0x5AFE),
            vrfCoordinator: coord,
            vrfKeyHash: keccak256("kh"),
            vrfSubId: 7,
            descriptor: descriptor
        });
    }

    // ------------------------------------------------------------- validate

    /// Audit Finding 2: a mainnet deploy refuses any non-canonical coordinator.
    function test_Validate_MainnetPinsCanonicalCoordinator() public {
        DeployConfig memory c = _goodConfig();
        vm.chainId(1);
        vm.expectRevert(bytes("config: not the canonical mainnet VRF coordinator"));
        harness.validate(c, deployer);
        // the canonical coordinator passes
        c.vrfCoordinator = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
        harness.validate(c, deployer);
        vm.chainId(31337);
    }

    function test_Validate_RejectsZeroInputs() public {
        DeployConfig memory c = _goodConfig();
        c.treasury = address(0);
        vm.expectRevert(bytes("config: treasury zero"));
        harness.validate(c, deployer);

        c = _goodConfig();
        c.pauseGuardian = address(0);
        vm.expectRevert(bytes("config: pauseGuardian zero"));
        harness.validate(c, deployer);

        c = _goodConfig();
        c.vrfSubId = 0;
        vm.expectRevert(bytes("config: vrfSubId zero"));
        harness.validate(c, deployer);

        // D-01: a zero gas-lane key hash bricks the seed request on genesis day
        c = _goodConfig();
        c.vrfKeyHash = bytes32(0);
        vm.expectRevert(bytes("config: vrfKeyHash zero"));
        harness.validate(c, deployer);
    }

    function test_Validate_RejectsDeployerAsPrivilegedParty() public {
        DeployConfig memory c = _goodConfig();
        c.pauseGuardian = deployer;
        vm.expectRevert(bytes("config: guardian == deployer EOA"));
        harness.validate(c, deployer);

        c = _goodConfig();
        c.treasury = deployer;
        vm.expectRevert(bytes("config: treasury == deployer EOA"));
        harness.validate(c, deployer);

        c = _goodConfig();
        c.reserveTreasury = deployer;
        vm.expectRevert(bytes("config: reserve == deployer EOA"));
        harness.validate(c, deployer);
    }

    function test_Validate_RejectsIdenticalPayees() public {
        DeployConfig memory c = _goodConfig();
        c.artist = c.treasury;
        vm.expectRevert(bytes("config: treasury == artist"));
        harness.validate(c, deployer);
    }

    /// The artists-allocation tail is a project grants pool; wiring it to the
    /// splitter artist payee is exactly the coupling reserveTreasury removed.
    function test_Validate_RejectsArtistPayeeAsReserve() public {
        DeployConfig memory c = _goodConfig();
        c.reserveTreasury = c.artist;
        vm.expectRevert(bytes("config: reserve == artist payee"));
        harness.validate(c, deployer);
    }

    /// Phase 7 flag 3 / doc §02: a zero descriptor is fatal in the production
    /// path (unset CP_DESCRIPTOR), same class as guardian == deployer.
    function test_Validate_RejectsZeroDescriptor() public {
        DeployConfig memory c = _goodConfig();
        c.descriptor = address(0);
        vm.expectRevert(bytes("config: descriptor zero (deploy Descriptor first)"));
        harness.validate(c, deployer);
    }

    // --------------------------------------------------- deploy + verify

    function test_DeployAndVerify_Passes() public {
        DeployConfig memory c = _goodConfig();
        vm.startPrank(deployer);
        DeployLib.Deployment memory d = DeployLib.deploy(c, deployer);
        vm.stopPrank();
        // verify is the deploy-time twin of I14/I11 — reverts on any mismatch
        DeployLib.verify(d, c);

        // spot-check the wiring the verify asserts
        assertEq(d.token.auctionHouse(), address(d.auctionHouse));
        assertEq(address(d.auctionHouse.token()), address(d.token));
        assertEq(d.auctionHouse.splitter(), address(d.splitter));
        assertEq(d.auctionHouse.pauseGuardian(), c.pauseGuardian);
        assertFalse(d.token.seedFulfilled());
        assertEq(d.auctionHouse.auction().startTime, 0);
    }

    /// The predicted-address wiring is exact: verify's token↔ah check would
    /// revert otherwise.
    function test_Deploy_CircularImmutablesResolve() public {
        DeployConfig memory c = _goodConfig();
        vm.startPrank(deployer);
        DeployLib.Deployment memory d = DeployLib.deploy(c, deployer);
        vm.stopPrank();
        assertEq(d.token.auctionHouse(), address(d.auctionHouse), "AH prediction wrong");
    }
}
