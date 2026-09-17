// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AuctionTerminal} from "../src/AuctionTerminal.sol";

contract AuctionTerminalTest is Test {
    function test_UiRoundTrips() public {
        string memory html = "<!DOCTYPE html><html><body>CYPHERPUNKS AUCTION TERMINAL</body></html>";
        AuctionTerminal t = new AuctionTerminal(html);
        assertEq(t.ui(), html);
        assertEq(t.length(), bytes(html).length);
    }

    function test_EmptyReverts() public {
        vm.expectRevert(bytes("empty ui"));
        new AuctionTerminal("");
    }

    /// The real page: round-trips byte-for-byte after the same placeholder
    /// substitution the deploy script performs, and carries the addresses
    /// and selectors a stranded user needs.
    function test_RealTerminalHtml_RoundTrips() public {
        string memory html = vm.readFile("script/terminal.html");
        assertTrue(vm.indexOf(html, "__TERMINAL_ADDRESS__") != type(uint256).max, "placeholder missing");
        html = vm.replace(html, "__TERMINAL_ADDRESS__", vm.toString(address(0xBEEF)));

        AuctionTerminal t = new AuctionTerminal(html);
        assertEq(t.ui(), html);
        assertEq(t.length(), bytes(html).length);

        // survival kit: auction house + token addresses, bid/settle/read selectors
        assertTrue(vm.indexOf(html, "0x6f99cb3d3A3c10bDAA52204509f3d85F4697f1B8") != type(uint256).max, "auction house missing");
        assertTrue(vm.indexOf(html, "0xA38ab198BE78d7Adf45652c522Cc6B4b8010520a") != type(uint256).max, "token missing");
        assertTrue(vm.indexOf(html, "0x659dd2b4") != type(uint256).max, "createBid selector missing");
        assertTrue(vm.indexOf(html, "0xf25efffc") != type(uint256).max, "settle selector missing");
        assertTrue(vm.indexOf(html, "0x7d9f6db5") != type(uint256).max, "auction() selector missing");
        assertTrue(vm.indexOf(html, "0xc87b56dd") != type(uint256).max, "tokenURI selector missing");
    }

    /// EIP-170 bound: the STOP prefix leaves 24575 bytes for the page.
    function test_MaxSize_RoundTrips() public {
        AuctionTerminal t = new AuctionTerminal(_filler(24575));
        assertEq(t.length(), 24575);
        assertEq(bytes(t.ui()).length, 24575);
    }

    /// Mainnet caps runtime code at 24576 bytes (EIP-170); the test EVM does
    /// not enforce it, so assert the real page honors the bound — and that
    /// the data contract stores exactly length+1 bytes (STOP prefix).
    function test_RealPage_WithinMainnetCodeSizeBound() public {
        string memory html = vm.readFile("script/terminal.html");
        html = vm.replace(html, "__TERMINAL_ADDRESS__", vm.toString(address(0xBEEF)));
        AuctionTerminal t = new AuctionTerminal(html);
        assertLe(bytes(html).length, 24575, "page exceeds EIP-170 deployable size");
        assertEq(t.pointer().code.length, bytes(html).length + 1);
    }

    function _filler(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            b[i] = bytes1(uint8(65 + (i % 26)));
        }
        return string(b);
    }
}
