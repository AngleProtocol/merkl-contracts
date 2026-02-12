// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { DistributionCreator } from "../contracts/DistributionCreator.sol";

contract DeployDistributionCreatorImplementation is BaseScript {
    // forge script scripts/deployDistributionCreatorImplementation.s.sol --rpc-url mainnet --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the DistributionCreator implementation
        DistributionCreator implementation = new DistributionCreator();
        
        console.log("DistributionCreator Implementation deployed at:", address(implementation));

        vm.stopBroadcast();
    }
}
