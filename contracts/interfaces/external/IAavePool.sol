// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

/// @title IAavePool
/// @notice Minimal interface for the Aave lending pool used to withdraw an underlying asset
interface IAavePool {
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
