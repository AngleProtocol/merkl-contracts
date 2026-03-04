// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { StandardMiddleman } from "../contracts/partners/middleman/StandardMiddleman.sol";
import { CampaignParameters } from "../contracts/DistributionCreator.sol";

contract DeployStandardMiddleman is BaseScript {
    // forge script scripts/deployStandardMiddleman.s.sol --rpc-url linea --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // ------------------------------------------------------------------------
        // DEPLOYMENT PARAMETERS
        address owner = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;

        // Executors
        address executor1 = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;

        // Default campaign parameters - TO EDIT
        // You can generate these using the Merkl campaign creation frontend
        CampaignParameters memory defaultParams = CampaignParameters({
            campaignId: bytes32(0),
            creator: address(0),
            rewardToken: address(0xD53f905D140dA38FB6505756A5D1eD14599BcdE5), // TO EDIT: Set reward token address
            amount: 0,
            campaignType: 4, // TO EDIT: Set campaign type
            startTimestamp: 0,
            duration: 3600, // TO EDIT: Set duration in seconds
            campaignData: hex"cd7b313f6fb732723e6a48935f34d18fd944050bccc526494e54de4b94dc1474" // TO EDIT: Set campaign data (encoded parameters)
        });
        // ------------------------------------------------------------------------

        // Deploy StandardMiddleman
        StandardMiddleman middleman = new StandardMiddleman(owner, distributionCreator);
        // StandardMiddleman middleman = 0xaaf4523EEa17159692eB8fA7DAd723c2972bE31b;
        console.log("StandardMiddleman deployed at:", address(middleman));

        // Add executors
        // middleman.setExecutor(executor1, 1);
        console.log("Executor added:", executor1);

        // Set default parameters if configured
        if (defaultParams.campaignData.length > 0) {
            middleman.setDefaultParameters(defaultParams);
            console.log("Default parameters set");
        } else {
            console.log("Warning: Default parameters not set - configure campaignData before use");
        }

        vm.stopBroadcast();
    }
}
