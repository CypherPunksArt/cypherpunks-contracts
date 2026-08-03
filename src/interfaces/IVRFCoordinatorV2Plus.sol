// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @dev Minimal Chainlink VRF v2.5 coordinator surface — hand-vendored ABI
///      matching smartcontractkit/chainlink
///      contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol
///      (struct RandomWordsRequest) and
///      contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol
///      (requestRandomWords). The full originals are vendored unmodified in
///      reference/chainlink/ for side-by-side review. The consumer base
///      (VRFConsumerBaseV2Plus) is deliberately NOT inherited: it drags in
///      ConfirmedOwner, and this system has no owner.
struct VRFV2PlusRequest {
    bytes32 keyHash;
    uint256 subId;
    uint16 requestConfirmations;
    uint32 callbackGasLimit;
    uint32 numWords;
    bytes extraArgs;
}

interface IVRFCoordinatorV2Plus {
    function requestRandomWords(VRFV2PlusRequest calldata req)
        external
        returns (uint256 requestId);
}
