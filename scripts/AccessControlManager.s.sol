// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { AccessControlManager } from "../contracts/AccessControlManager.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";

// Base contract with shared constants and utilities
contract AccessControlManagerScript is BaseScript {}

// AddGovernor script
contract AddGovernor is AccessControlManagerScript {
    function run(address governor) external {
        _run(governor);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE GOVERNOR TO ADD
        address governor = address(0);
        _run(governor);
    }

    function _run(address _governor) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address acmAddress = address(0);

        AccessControlManager(acmAddress).addGovernor(_governor);
        console.log("Governor added:", _governor);
    }
}

// RemoveGovernor script
contract RemoveGovernor is AccessControlManagerScript {
    function run(address governor) external {
        _run(governor);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE GOVERNOR TO REMOVE
        address governor = address(0);
        _run(governor);
    }

    function _run(address _governor) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address acmAddress = address(0);

        AccessControlManager(acmAddress).removeGovernor(_governor);
        console.log("Governor removed:", _governor);
    }
}

// SetAccessControlManager script
contract SetAccessControlManager is AccessControlManagerScript {
    function run(IAccessControlManager newAcm) external {
        _run(newAcm);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE NEW ACM ADDRESS
        address newAcmAddress = address(0);
        _run(IAccessControlManager(newAcmAddress));
    }

    function _run(IAccessControlManager _newAcm) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address acmAddress = address(0);

        AccessControlManager(acmAddress).setAccessControlManager(_newAcm);
        console.log("AccessControlManager updated to:", address(_newAcm));
    }
}

// CheckRoles script
contract CheckRoles is AccessControlManagerScript {
    function run(address account) external {
        _run(account);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE ACCOUNT TO CHECK
        address account = address(0);
        _run(account);
    }

    function _run(address _account) internal {
        uint256 chainId = block.chainid;
        // TODO: replace
        address acmAddress = address(0);
        AccessControlManager acm = AccessControlManager(acmAddress);

        bool isGovernor = acm.isGovernor(_account);
        bool isGuardian = acm.isGovernorOrGuardian(_account);

        console.log("Account:", _account);
        console.log("Is Governor:", isGovernor);
        console.log("Is Guardian:", isGuardian);
    }
}
