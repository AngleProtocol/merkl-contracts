// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Optimism Portal interface for proving withdrawals
interface IOptimismPortal {
    struct WithdrawalTransaction {
        uint256 nonce;
        address sender;
        address target;
        uint256 value;
        uint256 gasLimit;
        bytes data;
    }

    struct OutputRootProof {
        bytes32 version;
        bytes32 stateRoot;
        bytes32 messagePasserStorageRoot;
        bytes32 latestBlockhash;
    }

    function proveWithdrawalTransaction(
        WithdrawalTransaction memory _tx,
        uint256 _l2OutputIndex,
        OutputRootProof memory _outputRootProof,
        bytes[] memory _withdrawalProof
    ) external;

    function provenWithdrawals(bytes32 withdrawalHash) external view returns (bytes32 outputRoot, uint128 timestamp, uint128 l2OutputIndex);

    function isOutputFinalized(uint256 _l2OutputIndex) external view returns (bool);

    function finalizeWithdrawalTransaction(WithdrawalTransaction memory _tx) external;
}

/// @notice L2OutputOracle interface for getting L2 output data
interface IL2OutputOracle {
    struct OutputProposal {
        bytes32 outputRoot;
        uint128 timestamp;
        uint128 l2BlockNumber;
    }

    function getL2Output(uint256 _l2OutputIndex) external view returns (OutputProposal memory);

    function getL2OutputIndexAfter(uint256 _l2BlockNumber) external view returns (uint256);

    function latestBlockNumber() external view returns (uint256);
}

/// @title ProveBlastWithdrawal
/// @notice Foundry script to prove a withdrawal transaction from Blast L2 on Ethereum L1
/// @author Angle Labs
/// @dev This script uses FFI to fetch proofs from Blast L2 RPC
///
/// Usage:
///   forge script scripts/blast/ProveWithdrawal.s.sol:ProveBlastWithdrawal \
///     --sig "run(bytes32)" <L2_TX_HASH> \
///     --rpc-url mainnet \
///     --broadcast
contract ProveBlastWithdrawal is Script {
    using stdJson for string;

    // Blast Mainnet Addresses on Ethereum L1
    address constant OPTIMISM_PORTAL = 0x0Ec68c5B10F21EFFb74f2A5C61DFe6b08C0Db6Cb;
    address constant L2_OUTPUT_ORACLE = 0x826D1B0D4111Ad9146Eb8941D7Ca2B6a44215c76;
    address constant L2_TO_L1_MESSAGE_PASSER = 0x4200000000000000000000000000000000000016;

    // MessagePassed event signature - used to identify withdrawal transactions
    bytes32 constant MESSAGE_PASSED_EVENT = keccak256("MessagePassed(uint256,address,address,uint256,uint256,bytes,bytes32)");

    IOptimismPortal public portal;
    IL2OutputOracle public oracle;

    struct WithdrawalData {
        uint256 nonce;
        address sender;
        address target;
        uint256 value;
        uint256 gasLimit;
        bytes data;
        uint256 l2BlockNumber;
    }

    function setUp() public {
        portal = IOptimismPortal(OPTIMISM_PORTAL);
        oracle = IL2OutputOracle(L2_OUTPUT_ORACLE);
    }

    /// @notice Main function to prove a withdrawal
    /// @param l2TxHash The transaction hash on Blast L2
    /// Example: 0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1
    function run(bytes32 l2TxHash) public {
        _logHeader(l2TxHash);

        // Step 1: Fetch withdrawal data from Blast L2
        console.log("Step 1: Fetching withdrawal data from Blast L2...");
        WithdrawalData memory withdrawal = _fetchWithdrawalFromL2(l2TxHash);
        _logWithdrawalDetails(withdrawal);

        // Step 2: Build withdrawal transaction struct
        IOptimismPortal.WithdrawalTransaction memory tx = IOptimismPortal.WithdrawalTransaction({
            nonce: withdrawal.nonce,
            sender: withdrawal.sender,
            target: withdrawal.target,
            value: withdrawal.value,
            gasLimit: withdrawal.gasLimit,
            data: withdrawal.data
        });

        bytes32 withdrawalHash = _hashWithdrawal(tx);
        console.log("Withdrawal Hash:");
        console.logBytes32(withdrawalHash);
        console.log("");

        // Step 3: Check if already proven
        console.log("Step 2: Checking proof status on L1...");
        if (_checkIfProven(withdrawalHash)) {
            return; // Already proven, exit
        }

        // Step 4: Verify L2 output is available on L1
        console.log("Step 3: Verifying L2 output availability on L1...");
        _checkL2OutputAvailable(withdrawal.l2BlockNumber);

        // Step 5: Get L2 output data
        console.log("Step 4: Fetching L2 output data...");
        uint256 l2OutputIndex = oracle.getL2OutputIndexAfter(withdrawal.l2BlockNumber);
        IL2OutputOracle.OutputProposal memory outputProposal = oracle.getL2Output(l2OutputIndex);
        _logL2OutputData(l2OutputIndex, outputProposal);

        // Step 6: Generate withdrawal proofs
        console.log("Step 5: Generating withdrawal proofs...");
        bytes32 messageSlot = keccak256(abi.encode(withdrawalHash, uint256(0)));
        console.log("Storage Slot:");
        console.logBytes32(messageSlot);

        (bytes32 stateRoot, bytes32 blockHash, bytes32 storageRoot, bytes[] memory storageProof) = _getWithdrawalProof(
            messageSlot,
            uint32(outputProposal.l2BlockNumber)
        );

        _logProofData(stateRoot, blockHash, storageRoot, storageProof.length);

        // Step 7: Build output root proof
        IOptimismPortal.OutputRootProof memory outputRootProof = IOptimismPortal.OutputRootProof({
            version: bytes32(0),
            stateRoot: stateRoot,
            messagePasserStorageRoot: storageRoot,
            latestBlockhash: blockHash
        });

        // Step 8: Submit proof to L1
        _submitProof(tx, l2OutputIndex, outputRootProof, storageProof);
    }

    /// @notice Fetch withdrawal data from L2 transaction receipt
    function _fetchWithdrawalFromL2(bytes32 l2TxHash) internal returns (WithdrawalData memory withdrawal) {
        // Use cast to get the transaction receipt in JSON format
        string[] memory cmd = new string[](6);
        cmd[0] = "cast";
        cmd[1] = "receipt";
        cmd[2] = vm.toString(l2TxHash);
        cmd[3] = "--json";
        cmd[4] = "--rpc-url";
        cmd[5] = vm.rpcUrl("blast");

        bytes memory result = vm.ffi(cmd);
        string memory receiptJson = string(result);

        // Extract block number
        withdrawal.l2BlockNumber = receiptJson.readUint(".blockNumber");

        // Find MessagePassed event in logs
        uint256 logIndex = _findMessagePassedLog(receiptJson);

        string memory logPath = string.concat(".logs[", vm.toString(logIndex), "]");

        // Parse MessagePassed event
        // Topics: [event_sig, nonce, sender, target]
        withdrawal.nonce = uint256(receiptJson.readBytes32(string.concat(logPath, ".topics[1]")));
        withdrawal.sender = address(uint160(uint256(receiptJson.readBytes32(string.concat(logPath, ".topics[2]")))));
        withdrawal.target = address(uint160(uint256(receiptJson.readBytes32(string.concat(logPath, ".topics[3]")))));

        // Data: [value, gasLimit, data, withdrawalHash]
        bytes memory logData = receiptJson.readBytes(string.concat(logPath, ".data"));
        (withdrawal.value, withdrawal.gasLimit, withdrawal.data, ) = abi.decode(logData, (uint256, uint256, bytes, bytes32));
    }

    /// @notice Find the MessagePassed event log index
    function _findMessagePassedLog(string memory receiptJson) internal returns (uint256) {
        // MessagePassed event signature
        bytes32 messagePassedSig = MESSAGE_PASSED_EVENT;

        // Try to find the log with MessagePassed event from L2ToL1MessagePasser
        for (uint256 i = 0; i < 10; i++) {
            try vm.parseJsonBytes32(receiptJson, string.concat(".logs[", vm.toString(i), "].topics[0]")) returns (bytes32 topic0) {
                if (topic0 == messagePassedSig) {
                    // Check if it's from the L2ToL1MessagePasser contract
                    try vm.parseJsonAddress(receiptJson, string.concat(".logs[", vm.toString(i), "].address")) returns (address logAddress) {
                        if (logAddress == L2_TO_L1_MESSAGE_PASSER) {
                            console.log("Found MessagePassed event at log index:", i);
                            return i;
                        }
                    } catch {
                        continue;
                    }
                }
            } catch {
                // No more logs
                break;
            }
        }

        revert("MessagePassed event not found in transaction receipt");
    }

    /// @notice Get withdrawal proof using the helper script
    function _getWithdrawalProof(
        bytes32 slot,
        uint32 l2BlockNumber
    ) internal returns (bytes32 stateRoot, bytes32 blockHash, bytes32 storageRoot, bytes[] memory proof) {
        string memory blastRpc = vm.rpcUrl("blast");

        string[] memory cmd = new string[](3);
        cmd[0] = "bash";
        cmd[1] = "-c";
        cmd[2] = string.concat(
            "./scripts/blast/getWithdrawalProof.sh ",
            Strings.toHexString(uint256(slot)),
            " ",
            Strings.toString(l2BlockNumber),
            " ",
            blastRpc,
            " | jq"
        );

        bytes memory result = vm.ffi(cmd);
        string memory proofJson = string(result);

        stateRoot = proofJson.readBytes32("$.stateRoot");
        blockHash = proofJson.readBytes32("$.hash");
        storageRoot = proofJson.readBytes32("$.storageHash");
        proof = proofJson.readBytesArray("$.proof");
    }

    /// @notice Check if withdrawal is already proven
    function _checkIfProven(bytes32 withdrawalHash) internal view returns (bool) {
        (bytes32 outputRoot, uint128 timestamp, uint128 provenL2OutputIndex) = portal.provenWithdrawals(withdrawalHash);

        if (timestamp != 0) {
            console.log("Withdrawal already proven!");
            console.log("  Proven at timestamp:", timestamp);
            console.log("  Output root:");
            console.logBytes32(outputRoot);
            console.log("  L2 Output Index:", provenL2OutputIndex);

            bool finalized = portal.isOutputFinalized(provenL2OutputIndex);
            console.log("  Finalized:", finalized);

            if (finalized) {
                console.log("\n=== Withdrawal is finalized! ===");
                console.log("You can now call finalizeWithdrawalTransaction to claim your funds.");
            } else {
                console.log("\n=== Waiting for challenge period ===");
                console.log("Challenge period (~7 days) must pass before finalization.");
            }
            return true;
        }

        console.log("Withdrawal not yet proven. Proceeding...\n");
        return false;
    }

    /// @notice Verify L2 output is available on L1
    function _checkL2OutputAvailable(uint256 requiredBlock) internal view {
        uint256 latestBlock = oracle.latestBlockNumber();
        console.log("  Latest L2 block on L1:", latestBlock);
        console.log("  Required L2 block:", requiredBlock);

        if (latestBlock < requiredBlock) {
            console.log("\n=== ERROR: L2 output not yet available ===");
            console.log("L2 outputs are submitted to L1 approximately every hour.");
            console.log("Please wait and try again later.");
            revert("L2 output not available on L1");
        }

        console.log("L2 output is available!\n");
    }

    /// @notice Submit the proof transaction to L1
    function _submitProof(
        IOptimismPortal.WithdrawalTransaction memory tx,
        uint256 l2OutputIndex,
        IOptimismPortal.OutputRootProof memory outputRootProof,
        bytes[] memory storageProof
    ) internal {
        console.log("Step 6: Submitting proof to OptimismPortal...");
        console.log("Portal address:", OPTIMISM_PORTAL);
        console.log("Broadcaster:", vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")));
        console.log("");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        try portal.proveWithdrawalTransaction(tx, l2OutputIndex, outputRootProof, storageProof) {
            vm.stopBroadcast();
            console.log("=== SUCCESS ===");
            console.log("Withdrawal successfully proven on L1!");
            console.log("\nNext steps:");
            console.log("1. Wait ~7 days for the challenge period to pass");
            console.log("2. Call finalizeWithdrawalTransaction to claim your funds");
            console.log("\nMonitor status:");
            console.log("- Check Etherscan:", OPTIMISM_PORTAL);
            console.log("- Query provenWithdrawals(withdrawalHash)");
        } catch Error(string memory reason) {
            vm.stopBroadcast();
            console.log("=== TRANSACTION FAILED ===");
            console.log("Reason:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            vm.stopBroadcast();
            console.log("=== TRANSACTION FAILED ===");
            console.log("Low-level error:");
            console.logBytes(lowLevelData);
            revert("Transaction failed with low-level error");
        }
    }

    /// @notice Compute withdrawal hash (Optimism spec)
    function _hashWithdrawal(IOptimismPortal.WithdrawalTransaction memory tx) internal pure returns (bytes32) {
        return keccak256(abi.encode(tx.nonce, tx.sender, tx.target, tx.value, tx.gasLimit, tx.data));
    }

    // === Logging helpers ===

    function _logHeader(bytes32 txHash) internal pure {
        console.log("============================================");
        console.log("  Blast L2 -> Ethereum L1 Withdrawal Proof");
        console.log("============================================");
        console.log("");
        console.log("L2 Transaction Hash:");
        console.logBytes32(txHash);
        console.log("");
    }

    function _logWithdrawalDetails(WithdrawalData memory w) internal pure {
        console.log("Withdrawal Details:");
        console.log("  Nonce:", w.nonce);
        console.log("  Sender:", w.sender);
        console.log("  Target:", w.target);
        console.log("  Value:", w.value, "wei");
        console.log("  Gas Limit:", w.gasLimit);
        console.log("  Data length:", w.data.length, "bytes");
        console.log("  L2 Block:", w.l2BlockNumber);
        console.log("");
    }

    function _logL2OutputData(uint256 index, IL2OutputOracle.OutputProposal memory proposal) internal pure {
        console.log("L2 Output:");
        console.log("  Index:", index);
        console.log("  Block:", proposal.l2BlockNumber);
        console.log("  Timestamp:", proposal.timestamp);
        console.log("  Output Root:");
        console.logBytes32(proposal.outputRoot);
        console.log("");
    }

    function _logProofData(bytes32 stateRoot, bytes32 blockHash, bytes32 storageRoot, uint256 proofLength) internal pure {
        console.log("Proof Data:");
        console.log("  State Root:");
        console.logBytes32(stateRoot);
        console.log("  Block Hash:");
        console.logBytes32(blockHash);
        console.log("  Storage Root:");
        console.logBytes32(storageRoot);
        console.log("  Proof elements:", proofLength);
        console.log("");
    }
}
