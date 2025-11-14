// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";

/// @title AccessControlManager
/// @author Merkl SAS
/// @notice Manages role-based access control across all Merkl protocol contracts
/// @dev Implements a two-tier permission system with governor and guardian roles
/// @dev All governors automatically have guardian privileges
contract AccessControlManager is IAccessControlManager, Initializable, AccessControlEnumerableUpgradeable {
    /// @notice Role identifier for guardians (limited administrative privileges)
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    /// @notice Role identifier for governors (full administrative privileges)
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // =============================== Events ======================================

    event AccessControlManagerUpdated(address indexed _accessControlManager);

    // =============================== Errors ======================================

    error InvalidAccessControlManager();
    error IncompatibleGovernorAndGuardian();
    error NotEnoughGovernorsLeft();
    error ZeroAddress();

    /// @notice Initializes the AccessControlManager with initial governor and guardian
    /// @param governor Address to be granted the governor role (full administrative privileges)
    /// @param guardian Address to be granted the guardian role (limited administrative privileges)
    /// @dev Governor and guardian must be different non-zero addresses
    /// @dev Governor automatically receives both GOVERNOR_ROLE and GUARDIAN_ROLE
    /// @dev Sets GOVERNOR_ROLE as the admin role for both GOVERNOR_ROLE and GUARDIAN_ROLE
    function initialize(address governor, address guardian) public initializer {
        if (governor == address(0) || guardian == address(0)) revert ZeroAddress();
        if (governor == guardian) revert IncompatibleGovernorAndGuardian();
        _setupRole(GOVERNOR_ROLE, governor);
        _setupRole(GUARDIAN_ROLE, guardian);
        _setupRole(GUARDIAN_ROLE, governor);
        _setRoleAdmin(GUARDIAN_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(GOVERNOR_ROLE, GOVERNOR_ROLE);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // =========================== View Functions ==================================

    /// @inheritdoc IAccessControlManager
    function isGovernor(address admin) external view virtual returns (bool) {
        return hasRole(GOVERNOR_ROLE, admin);
    }

    /// @inheritdoc IAccessControlManager
    function isGovernorOrGuardian(address admin) external view returns (bool) {
        return hasRole(GUARDIAN_ROLE, admin);
    }

    // =========================== Governor Functions ==============================

    /// @notice Grants governor role to a new address
    /// @param governor Address to receive governor privileges
    /// @dev Must be called instead of grantRole to ensure the address receives both governor and guardian roles
    /// @dev Only existing governors can call this function
    function addGovernor(address governor) external {
        grantRole(GOVERNOR_ROLE, governor);
        grantRole(GUARDIAN_ROLE, governor);
    }

    /// @notice Revokes governor role from an address
    /// @param governor Address to lose governor privileges
    /// @dev Must be called instead of revokeRole to ensure both governor and guardian roles are removed
    /// @dev Cannot remove the last governor - at least one must remain
    /// @dev Only existing governors can call this function
    function removeGovernor(address governor) external {
        if (getRoleMemberCount(GOVERNOR_ROLE) <= 1) revert NotEnoughGovernorsLeft();
        revokeRole(GUARDIAN_ROLE, governor);
        revokeRole(GOVERNOR_ROLE, governor);
    }

    /// @notice Migrates to a new AccessControlManager contract
    /// @param _accessControlManager Address of the new AccessControlManager contract
    /// @dev Validates that all current governors are also governors in the new contract
    /// @dev After calling this, governance should also update all protocol contracts to use the new AccessControlManager
    /// @dev Only callable by existing governors
    function setAccessControlManager(IAccessControlManager _accessControlManager) external onlyRole(GOVERNOR_ROLE) {
        uint256 count = getRoleMemberCount(GOVERNOR_ROLE);
        bool success;
        for (uint256 i; i < count; ++i) {
            success = _accessControlManager.isGovernor(getRoleMember(GOVERNOR_ROLE, i));
            if (!success) break;
        }
        if (!success) revert InvalidAccessControlManager();
        emit AccessControlManagerUpdated(address(_accessControlManager));
    }
}
