// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IAccessControlManager } from "../interfaces/IAccessControlManager.sol";
import { Errors } from "./Errors.sol";

/// @title UUPSHelper
/// @notice Helper contract for UUPSUpgradeable contracts where the upgradeability is controlled by a specific address
/// @author Merkl SAS
/// @dev The 0 address check in the modifier allows the use of these modifiers during initialization
abstract contract UUPSHelper is UUPSUpgradeable {
    modifier onlyGuardianUpgrader(IAccessControlManager _accessControlManager) {
        if (address(_accessControlManager) != address(0) && !_accessControlManager.isGovernorOrGuardian(msg.sender))
            revert Errors.NotGovernorOrGuardian();
        _;
    }

    modifier onlyGovernorUpgrader(IAccessControlManager _accessControlManager) {
        if (address(_accessControlManager) != address(0) && !_accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    constructor() initializer {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override {}
}
