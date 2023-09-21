// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

/// @title ICore
/// @author Angle Labs, Inc.
/// @notice Interface for the `Core` contracts of smart contract modules used in Angle Labs contracts
interface ICore {
    /// @notice Checks whether an address is governor
    /// @param admin Address to check
    /// @return Whether the address has the `GOVERNOR_ROLE` or not
    function isGovernor(address admin) external view returns (bool);

    /// @notice Checks whether an address is a governor or a guardian of a module
    /// @param admin Address to check
    /// @return Whether the address has the `GUARDIAN_ROLE` or not
    /// @dev Governance should make sure when adding a governor to also give this governor the guardian
    /// role by calling the `addGovernor` function
    function isGovernorOrGuardian(address admin) external view returns (bool);
}
