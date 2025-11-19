// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IClaimRecipient } from "../interfaces/IClaimRecipient.sol";

/// @notice Mock contract that implements IClaimRecipient correctly
contract MockClaimRecipient is IClaimRecipient {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("IClaimRecipient.onClaim");

    address public lastUser;
    address public lastToken;
    uint256 public lastAmount;
    bytes public lastData;
    uint256 public callCount;

    function onClaim(address user, address token, uint256 amount, bytes memory data) external returns (bytes32) {
        lastUser = user;
        lastToken = token;
        lastAmount = amount;
        lastData = data;
        callCount++;
        return CALLBACK_SUCCESS;
    }
}

/// @notice Mock contract that implements IClaimRecipient incorrectly (returns wrong bytes32)
contract MockClaimRecipientWrongReturn is IClaimRecipient {
    function onClaim(address, address, uint256, bytes memory) external pure returns (bytes32) {
        return bytes32(0);
    }
}

/// @notice Mock contract without the IClaimRecipient interface
contract MockNonClaimRecipient {
    // No onClaim function
}
