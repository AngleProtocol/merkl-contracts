// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

/// @title IWETH
/// @notice Minimal interface for a wrapped native token (e.g. wETH) used to unwrap to the native token
interface IWETH {
    function withdraw(uint256 wad) external;
}
