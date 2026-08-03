// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CypherPunksManual} from "../src/Manual.sol";

contract ManualTest is Test {
    function test_ReadReturnsText() public {
        string memory txt =
            "How to bid: connect, enter an amount, place bid. How to settle: call settle once the clock ends. How to verify: read the contracts onchain.";
        CypherPunksManual m = new CypherPunksManual(txt);
        assertEq(m.read(), txt);
        assertEq(m.length(), bytes(txt).length);
    }

    function test_EmptyReverts() public {
        vm.expectRevert(bytes("empty manual"));
        new CypherPunksManual("");
    }

    function test_LongText_RoundTrips() public {
        // ~4KB to exercise SSTORE2 at a realistic manual size
        bytes memory b = new bytes(4096);
        for (uint256 i = 0; i < b.length; i++) {
            b[i] = bytes1(uint8(65 + (i % 26)));
        }
        string memory txt = string(b);
        CypherPunksManual m = new CypherPunksManual(txt);
        assertEq(m.read(), txt);
        assertEq(m.length(), 4096);
    }
}
