// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { SonicFragment } from "../contracts/partners/tokenWrappers/SonicFragment.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { AccessControlManager } from "../contracts/AccessControlManager.sol";

// forge script scripts/deploySonicFragment.s.sol:DeploySonicFragment --rpc-url sonic --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --verify -vvvv --broadcast -i 1
contract DeployAccessControlManager is BaseScript {
    function run() public broadcast {
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Deploy implementation
        AccessControlManager implementation = new AccessControlManager();
        console.log("ACM deployed at:", address(implementation));
    }
}
