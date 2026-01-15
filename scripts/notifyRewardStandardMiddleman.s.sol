// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StandardMiddleman } from "../contracts/partners/middleman/StandardMiddleman.sol";
import { CampaignParameters } from "../contracts/DistributionCreator.sol";

contract NotifyRewardStandardMiddleman is BaseScript {
    // Simulate:
    // forge script scripts/notifyRewardStandardMiddleman.s.sol --rpc-url linea --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701
    //
    // Execute:
    // forge script scripts/notifyRewardStandardMiddleman.s.sol --rpc-url linea --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address executor = vm.addr(deployerPrivateKey);

        // ------------------------------------------------------------------------
        // PARAMETERS TO EDIT
        address middlemanAddress = address(0x05F0c7Ca7B90e3786603108D42cA8DFd28d72075); // TO EDIT: Set deployed StandardMiddleman address
        uint256 amount = 100000000000000000000000; // TO EDIT: Set amount to distribute (in token wei)
        // ------------------------------------------------------------------------

        StandardMiddleman middleman = StandardMiddleman(middlemanAddress);

        // Fetch contract state for logging
        // defaultParams() returns tuple components, we only need rewardToken (index 2)
        (,, address rewardToken,,,,,) = middleman.defaultParams();
        address distributionCreator = address(middleman.merklDistributionCreator());

        console.log("=== StandardMiddleman NotifyReward ===");
        console.log("Middleman address:", middlemanAddress);
        console.log("Executor:", executor);
        console.log("Reward token:", rewardToken);
        console.log("Distribution creator:", distributionCreator);
        console.log("Amount to distribute:", amount);
        console.log("");

        // Check if executor is whitelisted
        uint256 executorStatus = middleman.executors(executor);
        console.log("Executor status:", executorStatus);
        require(executorStatus != 0, "Executor not whitelisted");


        // Check current middleman token balance
        uint256 middlemanBalance = IERC20(rewardToken).balanceOf(middlemanAddress);
        console.log("Middleman current token balance:", middlemanBalance);

        vm.startBroadcast(deployerPrivateKey);

        // Transfer tokens to the middleman contract
        if (middlemanBalance < amount) {
            uint256 transferAmount = amount - middlemanBalance;
            console.log("");
            console.log("Transferring tokens to middleman:", transferAmount);
            IERC20(rewardToken).transfer(middlemanAddress, transferAmount);
        }

        // Call notifyReward
        console.log("");
        console.log("Calling notifyReward with amount:", amount);
        middleman.notifyReward(amount);

        console.log("");
        console.log("=== notifyReward executed successfully ===");

        vm.stopBroadcast();
    }
}
