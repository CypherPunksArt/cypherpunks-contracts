// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {CypherPunksToken} from "../../src/Token.sol";
import {IDescriptor} from "../../src/interfaces/IDescriptor.sol";

/// Test-only harness: exposes the internal write-once seed hook so suites
/// that are not about VRF can seed directly. The production path is
/// requestSeed()/reRequest() → coordinator → rawFulfillRandomWords, covered
/// in test/VRF.t.sol against the mock coordinator.
contract TokenHarness is CypherPunksToken {
    constructor(
        address auctionHouse_,
        address artistTreasury_,
        address teamTreasury_,
        address vrfCoordinator_
    )
        CypherPunksToken(
            auctionHouse_,
            artistTreasury_,
            teamTreasury_,
            vrfCoordinator_,
            bytes32(uint256(1)), // test key hash
            1, // test sub id
            IDescriptor(address(0))
        )
    {}

    function writeSeedForTest(uint256 word) external {
        _writeSeed(word);
    }
}
