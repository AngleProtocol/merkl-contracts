// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { UpgradeDeploymentBase } from "./utils/UpgradeDeploymentBase.s.sol";

/// @title DeployUpgradeImplementationsSingle
/// @notice Deploys new implementations of DistributionCreator and Distributor for a single chain
/// @dev Run with: forge script scripts/deployUpgradeImplementationsSingle.s.sol --rpc-url <chain> --broadcast --verify
contract DeployUpgradeImplementationsSingle is UpgradeDeploymentBase {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        uint256 chainId = block.chainid;

        console.log("==========================================================");
        console.log("Deploying Upgrade Implementations");
        console.log("==========================================================");
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementations using base contract function
        (address distributionCreatorImpl, address distributorImpl) = _deployImplementations();

        vm.stopBroadcast();

        // Get chain name from base contract
        string memory chainName = _getChainName(chainId);

        // Save deployment results using base contract function
        DeploymentResult memory result = DeploymentResult({
            distributionCreatorImpl: distributionCreatorImpl,
            distributorImpl: distributorImpl,
            timestamp: block.timestamp,
            chainId: chainId,
            chainName: chainName,
            deployer: deployer,
            status: "SUCCESS",
            error: ""
        });

        _saveDeploymentResult(result);

        console.log("");
        console.log("==========================================================");
        console.log("Deployment Complete!");
        console.log("==========================================================");
        console.log(
            "Deployment file saved to:",
            string.concat("./deployments/", chainName, "-upgrade-implementations.json")
        );
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify the implementations on block explorer if not auto-verified");
        console.log("2. Use these addresses to create Gnosis Safe upgrade transactions");
        console.log("==========================================================");
    }
}
