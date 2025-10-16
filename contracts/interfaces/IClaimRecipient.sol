// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

/// @title IClaimRecipient
/// @author Merkl SAS
/// @notice Interface for the `ClaimRecipient` contracts expected by the `Distributor` contract
interface IClaimRecipient {
    /// @notice Hook to call within contracts receiving token rewards on behalf of users
    function onClaim(address user, address token, uint256 amount, bytes memory data) external returns (bytes32);
}
