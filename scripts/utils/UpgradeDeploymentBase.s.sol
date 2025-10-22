// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { DistributionCreator } from "../../contracts/DistributionCreator.sol";
import { Distributor } from "../../contracts/Distributor.sol";

/// @title UpgradeDeploymentBase
/// @notice Base contract for upgrade implementation deployment scripts
/// @dev Contains shared structs, chain configurations, and utility functions
abstract contract UpgradeDeploymentBase is Script {
    using stdJson for string;

    // Shared structs
    struct ChainConfig {
        string name;
        uint256 chainId;
        bool skipVerification;
    }

    struct DeploymentResult {
        address distributionCreatorImpl;
        address distributorImpl;
        uint256 timestamp;
        uint256 chainId;
        string chainName;
        address deployer;
        string status;
        string error;
    }

    /// @notice Get all supported chain configurations (SINGLE SOURCE OF TRUTH)
    /// @return Array of ChainConfig structs
    function _getChainConfigs() internal pure returns (ChainConfig[] memory) {
        ChainConfig[] memory configs = new ChainConfig[](52);

        configs[0] = ChainConfig("mainnet", 1, false);
        configs[1] = ChainConfig("polygon", 137, false);
        configs[2] = ChainConfig("fantom", 250, false);
        configs[3] = ChainConfig("optimism", 10, false);
        configs[4] = ChainConfig("arbitrum", 42161, false);
        configs[5] = ChainConfig("avalanche", 43114, false);
        configs[6] = ChainConfig("bsc", 56, false);
        configs[7] = ChainConfig("gnosis", 100, false);
        configs[8] = ChainConfig("polygonzkevm", 1101, false);
        configs[9] = ChainConfig("base", 8453, false);
        configs[10] = ChainConfig("bob", 60808, false);
        configs[11] = ChainConfig("linea", 59144, false);
        configs[12] = ChainConfig("mantle", 5000, false);
        configs[13] = ChainConfig("blast", 81457, false);
        configs[14] = ChainConfig("mode", 34443, false);
        configs[15] = ChainConfig("thundercore", 108, false);
        configs[16] = ChainConfig("coredao", 1116, false);
        configs[17] = ChainConfig("xlayer", 196, false);
        configs[18] = ChainConfig("taiko", 167000, false);
        configs[19] = ChainConfig("fuse", 122, false);
        configs[20] = ChainConfig("immutable", 13371, false);
        configs[21] = ChainConfig("scroll", 534352, false);
        configs[22] = ChainConfig("manta", 169, false);
        configs[23] = ChainConfig("sei", 1329, false);
        configs[24] = ChainConfig("celo", 42220, false);
        configs[25] = ChainConfig("fraxtal", 252, false);
        configs[26] = ChainConfig("astar", 592, false);
        configs[27] = ChainConfig("rootstock", 30, false);
        configs[28] = ChainConfig("moonbeam", 1284, false);
        configs[29] = ChainConfig("skale", 2046399126, false);
        configs[30] = ChainConfig("worldchain", 480, false);
        configs[31] = ChainConfig("lisk", 1135, false);
        configs[32] = ChainConfig("etherlink", 42793, false);
        configs[33] = ChainConfig("swell", 1923, false);
        configs[34] = ChainConfig("sonic", 146, false);
        configs[35] = ChainConfig("corn", 21000000, false);
        configs[36] = ChainConfig("ink", 57073, false);
        configs[37] = ChainConfig("ronin", 2020, false);
        configs[38] = ChainConfig("flow", 747, false);
        configs[39] = ChainConfig("berachain", 80094, true); // Often testnet
        configs[40] = ChainConfig("nibiru", 6900, false);
        configs[41] = ChainConfig("zircuit", 48900, false);
        configs[42] = ChainConfig("apechain", 33139, false);
        configs[43] = ChainConfig("hyperevm", 999, false);
        configs[44] = ChainConfig("hemi", 43111, false);
        configs[45] = ChainConfig("xdc", 50, false);
        configs[46] = ChainConfig("katana", 747474, true);
        configs[47] = ChainConfig("tac", 239, false);
        configs[48] = ChainConfig("plasma", 9745, false);
        configs[49] = ChainConfig("mezo", 31612, false);
        configs[50] = ChainConfig("redbelly", 151, false);
        configs[51] = ChainConfig("saga", 5464, false);

        return configs;
    }

    /// @notice Get chain name from chain ID by looking up in chain configs
    /// @param chainId The chain ID to look up
    /// @return The chain name, or "chain-<id>" if not found
    function _getChainName(uint256 chainId) internal pure returns (string memory) {
        ChainConfig[] memory configs = _getChainConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].chainId == chainId) {
                return configs[i].name;
            }
        }

        return string.concat("chain-", vm.toString(chainId));
    }

    /// @notice Deploy implementations on the current chain
    /// @return distributionCreatorImpl The deployed DistributionCreator implementation address
    /// @return distributorImpl The deployed Distributor implementation address
    function _deployImplementations() internal returns (address distributionCreatorImpl, address distributorImpl) {
        console.log("Deploying DistributionCreator implementation...");
        DistributionCreator dcImpl = new DistributionCreator();
        distributionCreatorImpl = address(dcImpl);
        console.log("DistributionCreator Implementation:", distributionCreatorImpl);

        console.log("Deploying Distributor implementation...");
        Distributor dImpl = new Distributor();
        distributorImpl = address(dImpl);
        console.log("Distributor Implementation:", distributorImpl);

        return (distributionCreatorImpl, distributorImpl);
    }

    /// @notice Save deployment results to JSON file
    /// @param result The deployment result to save
    function _saveDeploymentResult(DeploymentResult memory result) internal {
        string memory obj = "deployment";

        vm.serializeUint(obj, "chainId", result.chainId);
        vm.serializeString(obj, "chainName", result.chainName);
        vm.serializeAddress(obj, "distributionCreatorImplementation", result.distributionCreatorImpl);
        vm.serializeAddress(obj, "distributorImplementation", result.distributorImpl);
        vm.serializeUint(obj, "timestamp", result.timestamp);
        vm.serializeAddress(obj, "deployer", result.deployer);

        // Optional fields for multi-chain deployment
        if (bytes(result.status).length > 0) {
            vm.serializeString(obj, "status", result.status);
        }
        if (bytes(result.error).length > 0) {
            vm.serializeString(obj, "error", result.error);
        }

        string memory finalJson = vm.serializeString(obj, "_note", "Upgrade implementation deployment");

        // Write to file
        string memory fileName = string.concat("./deployments/", result.chainName, "-upgrade-implementations.json");
        vm.writeJson(finalJson, fileName);

        console.log("Deployment data saved to:", fileName);
    }

    /// @notice Convert string to uppercase (for environment variable names)
    /// @param str The string to convert
    /// @return The uppercase string
    function _toUpperCase(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bUpper = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; i++) {
            // Convert lowercase letters to uppercase
            if (uint8(bStr[i]) >= 97 && uint8(bStr[i]) <= 122) {
                bUpper[i] = bytes1(uint8(bStr[i]) - 32);
            } else {
                bUpper[i] = bStr[i];
            }
        }

        return string(bUpper);
    }
}
