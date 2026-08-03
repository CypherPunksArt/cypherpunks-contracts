// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {VRFV2PlusRequest} from "../../src/interfaces/IVRFCoordinatorV2Plus.sol";

interface IVRFConsumer {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

/// Minimal hand-written VRF v2.5 coordinator mock, modeled on Chainlink's
/// VRFCoordinatorV2_5Mock (test-only; provenance noted in the Phase 5
/// receipt). Records requests, lets tests drive fulfillment explicitly.
contract VRFCoordinatorV2PlusMock {
    uint256 public requestIdCounter;
    mapping(uint256 => address) public consumerOf;
    mapping(uint256 => VRFV2PlusRequest) public requestOf;

    function requestRandomWords(VRFV2PlusRequest calldata req)
        external
        returns (uint256 requestId)
    {
        requestId = ++requestIdCounter;
        consumerOf[requestId] = msg.sender;
        requestOf[requestId] = req;
    }

    /// Drive a fulfillment as the coordinator.
    function fulfill(uint256 requestId, uint256 word) external {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        IVRFConsumer(consumerOf[requestId]).rawFulfillRandomWords(requestId, words);
    }

    /// Drive a fulfillment toward an arbitrary consumer/request id (for
    /// unknown-request tests).
    function fulfillTo(address consumer, uint256 requestId, uint256 word) external {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        IVRFConsumer(consumer).rawFulfillRandomWords(requestId, words);
    }

    function extraArgsOf(uint256 requestId) external view returns (bytes memory) {
        return requestOf[requestId].extraArgs;
    }
}
