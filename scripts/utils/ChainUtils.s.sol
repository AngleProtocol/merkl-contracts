// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { BaseScript } from "./Base.s.sol";

// Interface for scripts that can be executed across chains
interface IMultiChainScript {
    function executeOnChain() external;
    function executeOnChain(bytes calldata data) external;
}

contract ChainUtils is Script {
    struct FailedChain {
        string network;
        uint256 chainId;
        string reason;
    }

    struct ExecutionResult {
        string network;
        uint256 chainId;
        bool success;
        string reason;
        bytes returnData;
    }

    // Events for better tracking
    event ChainExecutionStarted(string network, uint256 chainId);
    event ChainExecutionCompleted(string network, uint256 chainId, bool success);
    event ChainExecutionFailed(string network, uint256 chainId, string reason);

    // Registry verification function
    function verifyRegistryAddresses(address _distributor, address _core, address _multisig, address _proxyAdmin) public view {
        bytes memory coreData;
        (bool success, bytes memory returnData) = _distributor.staticcall(abi.encodeWithSignature("core()"));
        if (success) {
            coreData = returnData;
        } else {
            (bool success2, bytes memory returnData2) = _distributor.staticcall(abi.encodeWithSignature("accessControlManager()"));
            require(success2, "Invalid accessControlManager()");
            coreData = returnData2;
        }

        // We need to skip the first 12 bytes (function selector + padding) to get the address
        address core = address(uint160(uint256(bytes32(coreData))));
        bytes32 proxyAdminData = vm.load(core, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103);
        address proxyAdmin = address(uint160(uint256(proxyAdminData)));
        address multisig = ProxyAdmin(proxyAdmin).owner();

        if (core != _core) {
            console.log("Core merkl mismatch for chain", block.chainid);
        }

        if (proxyAdmin != _proxyAdmin) {
            console.log("Proxy admin mismatch for chain", block.chainid);
        }

        if (multisig != _multisig) {
            console.log("Multisig mismatch for chain", block.chainid);
        }
    }

    // Multi-chain execution logic (can be used by script contracts that inherit this)
    function executeAcrossChains(address scriptContract, bytes memory data, bool verificationOnly) internal {
        // Get all networks from foundry.toml
        string[2][] memory networks = vm.rpcUrls();

        // Track results
        ExecutionResult[] memory results = new ExecutionResult[](networks.length);
        uint256 totalChains = 0;
        uint256 successCount = 0;
        uint256 failedCount = 0;

        if (verificationOnly) {
            console.log("=== MULTICHAIN VERIFICATION STARTED ===");
        } else {
            console.log("=== MULTICHAIN EXECUTION STARTED ===");
        }

        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i][0];

            // Skip localhost, fork, and zksync
            if (
                keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("localhost")) ||
                keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("fork")) ||
                keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("zksync"))
            ) {
                continue;
            }

            // Create fork for this network
            bool forkSuccess = true;
            try vm.createSelectFork(network) {
                // Fork creation succeeded
            } catch {
                forkSuccess = false;
                console.log("[FAILED] Failed to create fork for network:", network);
            }
            if (forkSuccess) {
                uint256 chainId = block.chainid;
                emit ChainExecutionStarted(network, chainId);

                results[totalChains] = ExecutionResult({ network: network, chainId: chainId, success: false, reason: "", returnData: "" });

                if (verificationOnly) {
                    // Perform registry verification
                    address _distributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
                    // TODO: replace
                    address _core = address(0);
                    address _multisig = address(0);
                    address _proxyAdmin = address(0);

                    verifyRegistryAddresses(_distributor, _core, _multisig, _proxyAdmin);
                    results[totalChains].success = true;
                    successCount++;
                    console.log("[SUCCESS] Verification completed for", network);
                    console.log("Chain ID:", chainId);
                } else {
                    // Execute script
                    (bool scriptSuccess, string memory errorReason) = executeScript(scriptContract, data);

                    if (scriptSuccess) {
                        results[totalChains].success = true;
                        successCount++;
                        emit ChainExecutionCompleted(network, chainId, true);
                        console.log("[SUCCESS] Script execution completed for", network);
                        console.log("Chain ID:", chainId);
                    } else {
                        results[totalChains].reason = errorReason;
                        failedCount++;
                        emit ChainExecutionFailed(network, chainId, errorReason);
                        console.log("[FAILED] Script execution failed for", network);
                        console.log("Chain ID:", chainId);
                        console.log("Reason:", errorReason);
                    }
                }

                totalChains++;
            }
        }

        // Display summary
        displaySummary(results, totalChains, successCount, failedCount, verificationOnly);
    }

    // Execute a specific script with error handling
    function executeScript(address scriptContract, bytes memory data) internal virtual returns (bool success, string memory errorReason) {
        if (scriptContract == address(0)) {
            return (false, "Script contract cannot be zero address");
        }

        // Try different execution methods based on what the script supports
        if (data.length > 0) {
            // Try to call with data first
            (bool success1, ) = scriptContract.call(abi.encodeWithSignature("executeOnChain(bytes)", data));
            if (success1) {
                return (true, "");
            }
        }

        // Fall back to parameterless execution
        (bool success2, ) = scriptContract.call(abi.encodeWithSignature("executeOnChain()"));

        if (success2) {
            return (true, "");
        }

        // If both fail, try calling the run() function directly
        (bool success3, ) = scriptContract.call(abi.encodeWithSignature("run()"));
        if (success3) {
            return (true, "");
        }

        return (false, "All script execution methods failed");
    }

    // Execute script on a single chain
    function executeOnSingleChain(
        string calldata network,
        address scriptContract,
        bytes memory data
    ) internal returns (bool success, string memory errorReason) {
        try vm.createSelectFork(network) {
            uint256 chainId = block.chainid;
            console.log("Executing script on", network);
            console.log("Chain ID:", chainId);

            return executeScript(scriptContract, data);
        } catch {
            return (false, "Failed to create fork for network");
        }
    }

    function displaySummary(
        ExecutionResult[] memory results,
        uint256 totalChains,
        uint256 successCount,
        uint256 failedCount,
        bool verificationOnly
    ) internal pure {
        console.log("");
        if (verificationOnly) {
            console.log("=== MULTICHAIN VERIFICATION SUMMARY ===");
        } else {
            console.log("=== MULTICHAIN EXECUTION SUMMARY ===");
        }
        console.log("Total chains processed:", totalChains);
        console.log("Successful chains:", successCount);
        console.log("Failed chains:", failedCount);

        if (failedCount > 0) {
            console.log("");
            console.log("Failed chains details:");
            for (uint256 i = 0; i < totalChains; i++) {
                if (!results[i].success) {
                    console.log("- Network:", results[i].network);
                    console.log("  Chain ID:", results[i].chainId);
                    console.log("  Reason:", results[i].reason);
                }
            }
        }

        console.log("");
        if (verificationOnly) {
            console.log("Multichain verification completed!");
        } else {
            console.log("Multichain execution completed!");
        }
    }
}

// Script contract for running ChainUtils operations
contract ChainUtilsScript is BaseScript, ChainUtils {
    // Original verification-only run function
    function run() external {
        runVerification();
    }

    // Execute script across all chains
    function runScript(address scriptContract) external {
        bytes memory emptyData = "";
        executeAcrossChains(scriptContract, emptyData, false);
    }

    function runScript(address scriptContract, bytes memory data) external {
        executeAcrossChains(scriptContract, data, false);
    }

    // Execute script on a single specific chain
    function runScriptOnChain(string calldata network, address scriptContract) external {
        bytes memory emptyData = "";
        (bool success, string memory errorReason) = executeOnSingleChain(network, scriptContract, emptyData);

        if (success) {
            console.log("[SUCCESS] Script executed successfully on", network);
        } else {
            console.log("[FAILED] Script failed on", network);
            console.log("Reason:", errorReason);
        }
    }

    function runScriptOnChain(string calldata network, address scriptContract, bytes memory data) external {
        (bool success, string memory errorReason) = executeOnSingleChain(network, scriptContract, data);

        if (success) {
            console.log("[SUCCESS] Script executed successfully on", network);
        } else {
            console.log("[FAILED] Script failed on", network);
            console.log("Reason:", errorReason);
        }
    }

    // Verify registries across all chains
    function runVerification() public {
        bytes memory emptyData = "";
        executeAcrossChains(address(0), emptyData, true);
    }

    // Verify registry on a single chain
    function runVerificationOnChain(string calldata network) external {
        vm.createSelectFork(network);
        uint256 chainId = block.chainid;

        address _distributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
        // TODO: replace
        address _core = address(0);
        address _multisig = address(0);
        address _proxyAdmin = address(0);

        verifyRegistryAddresses(_distributor, _core, _multisig, _proxyAdmin);
        console.log("[SUCCESS] Registry verification completed for", network);
    }
}
