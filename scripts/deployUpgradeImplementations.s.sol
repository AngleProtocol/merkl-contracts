// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { UpgradeDeploymentBase } from "./utils/UpgradeDeploymentBase.s.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { Distributor } from "../contracts/Distributor.sol";

/// @title DeployUpgradeImplementations
/// @notice Deploys new implementations of DistributionCreator and Distributor for upgrades
/// @dev This script deploys new implementation contracts across all chains and saves the addresses
///      to separate JSON files per chain for easy Gnosis Safe transaction drafting
contract DeployUpgradeImplementations is UpgradeDeploymentBase {
    // All supported chains from foundry.toml
    ChainConfig[] public chains;

    function setUp() public {
        // Initialize chain configurations from base
        ChainConfig[] memory configs = _getChainConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            chains.push(configs[i]);
        }
    }

    /// @notice Main deployment function
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("Deploying Upgrade Implementations");
        console.log("Deployer:", deployer);
        console.log("==========================================================");
        console.log("");

        // Deploy on all chains
        for (uint256 i = 0; i < chains.length; i++) {
            _deployOnChain(chains[i], deployerPrivateKey, deployer);
        }

        console.log("");
        console.log("==========================================================");
        console.log("Deployment Complete!");
        console.log("Check ./deployments/ folder for individual chain results");
        console.log("==========================================================");
    }

    /// @notice Public wrapper for _deployImplementations to enable try/catch
    function deployImplementationsWrapper() external returns (address, address) {
        return _deployImplementations();
    }

    /// @notice Deploy on a specific chain with error handling
    function _deployOnChain(ChainConfig memory chainConfig, uint256 privateKey, address deployer) internal {
        console.log("----------------------------------------------------------");
        console.log(string.concat("Chain: ", chainConfig.name));
        console.log("Chain ID:", chainConfig.chainId);

        // Fork the chain
        string memory rpcEnvVar = string.concat(_toUpperCase(chainConfig.name), "_NODE_URI");
        string memory rpcUrl;

        try vm.envString(rpcEnvVar) returns (string memory url) {
            rpcUrl = url;
        } catch {
            console.log("SKIPPED: RPC URL not configured");
            _saveDeploymentResult(
                DeploymentResult({
                    distributionCreatorImpl: address(0),
                    distributorImpl: address(0),
                    timestamp: block.timestamp,
                    chainId: chainConfig.chainId,
                    chainName: chainConfig.name,
                    deployer: deployer,
                    status: "SKIPPED",
                    error: "RPC URL not configured"
                })
            );
            console.log("");
            return;
        }

        // Create fork
        uint256 forkId;
        try vm.createFork(rpcUrl) returns (uint256 id) {
            forkId = id;
            vm.selectFork(forkId);
        } catch {
            console.log("ERROR: Failed to create fork");
            _saveDeploymentResult(
                DeploymentResult({
                    distributionCreatorImpl: address(0),
                    distributorImpl: address(0),
                    timestamp: block.timestamp,
                    chainId: chainConfig.chainId,
                    chainName: chainConfig.name,
                    deployer: deployer,
                    status: "ERROR",
                    error: "Failed to create fork - RPC may be down"
                })
            );
            console.log("");
            return;
        }

        // Verify chain ID matches
        if (block.chainid != chainConfig.chainId) {
            console.log("ERROR: Chain ID mismatch");
            console.log("Expected:", chainConfig.chainId);
            console.log("Got:", block.chainid);
            _saveDeploymentResult(
                DeploymentResult({
                    distributionCreatorImpl: address(0),
                    distributorImpl: address(0),
                    timestamp: block.timestamp,
                    chainId: chainConfig.chainId,
                    chainName: chainConfig.name,
                    deployer: deployer,
                    status: "ERROR",
                    error: "Chain ID mismatch"
                })
            );
            console.log("");
            return;
        }

        // Start broadcasting transactions
        vm.startBroadcast(privateKey);

        address distributionCreatorImpl;
        address distributorImpl;
        string memory errorMsg = "";

        // Deploy implementations using base contract function
        try this.deployImplementationsWrapper() returns (address dcImpl, address dImpl) {
            distributionCreatorImpl = dcImpl;
            distributorImpl = dImpl;
        } catch Error(string memory reason) {
            errorMsg = string.concat("Failed to deploy: ", reason);
            console.log("ERROR:", errorMsg);
        } catch (bytes memory lowLevelData) {
            errorMsg = "Failed to deploy: Low-level error";
            console.log("ERROR:", errorMsg);
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();

        // Determine status
        string memory status;
        if (bytes(errorMsg).length > 0) {
            status = "ERROR";
        } else if (distributionCreatorImpl != address(0) && distributorImpl != address(0)) {
            status = "SUCCESS";
            console.log("SUCCESS: Both implementations deployed");

            // Verify contracts if not skipped
            if (!chainConfig.skipVerification) {
                _verifyContracts(chainConfig.name, distributionCreatorImpl, distributorImpl);
            }
        } else {
            status = "PARTIAL";
            errorMsg = "Some deployments failed";
        }

        // Save deployment result
        _saveDeploymentResult(
            DeploymentResult({
                distributionCreatorImpl: distributionCreatorImpl,
                distributorImpl: distributorImpl,
                timestamp: block.timestamp,
                chainId: chainConfig.chainId,
                chainName: chainConfig.name,
                deployer: deployer,
                status: status,
                error: errorMsg
            })
        );

        console.log("");
    }

    /// @notice Verify contracts on block explorer
    function _verifyContracts(string memory chainName, address distributionCreator, address distributor) internal {
        console.log("Verifying contracts...");

        // Verify DistributionCreator
        try vm.tryFfi(_buildVerifyCommand(chainName, distributionCreator, "DistributionCreator")) {
            console.log("DistributionCreator verified");
        } catch {
            console.log("Warning: DistributionCreator verification failed (run manually if needed)");
        }

        // Verify Distributor
        try vm.tryFfi(_buildVerifyCommand(chainName, distributor, "Distributor")) {
            console.log("Distributor verified");
        } catch {
            console.log("Warning: Distributor verification failed (run manually if needed)");
        }
    }

    /// @notice Build verification command
    function _buildVerifyCommand(
        string memory chainName,
        address contractAddress,
        string memory contractName
    ) internal pure returns (string[] memory) {
        string[] memory args = new string[](7);
        args[0] = "forge";
        args[1] = "verify-contract";
        args[2] = vm.toString(contractAddress);
        args[3] = string.concat("contracts/", contractName, ".sol:", contractName);
        args[4] = "--chain";
        args[5] = chainName;
        args[6] = "--watch";
        return args;
    }
}
