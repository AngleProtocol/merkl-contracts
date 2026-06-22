// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

/// @title IAaveToken
/// @notice Minimal interface for an Aave aToken, exposing its pool and underlying asset
interface IAaveToken {
    function POOL() external view returns (address);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
