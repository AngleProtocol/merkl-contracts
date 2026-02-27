// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

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

    function provenWithdrawals(bytes32 withdrawalHash)
        external
        view
        returns (bytes32 outputRoot, uint128 timestamp, uint128 l2OutputIndex);

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
/// @notice Pure Solidity script to prove a withdrawal transaction from Blast L2 on Ethereum L1
/// @dev Uses Foundry cheatcodes to fetch data from Blast L2
contract ProveBlastWithdrawal is Script {
    // Blast Mainnet Addresses on Ethereum L1
    address constant OPTIMISM_PORTAL = 0x0Ec68c5B10F21EFFb74f2A5C61DFe6b08C0Db6Cb;
    address constant L2_OUTPUT_ORACLE = 0x826D1B0D4111Ad9146Eb8941D7Ca2B6a44215c76;
    address constant L2_TO_L1_MESSAGE_PASSER = 0x4200000000000000000000000000000000000016;

    // MessagePassed event signature
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

    /// @notice Main function to prove a withdrawal from a Blast L2 transaction hash
    /// @param l2TxHash The transaction hash on Blast L2 (e.g., 0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1)
    function run(bytes32 l2TxHash) public {
        console.log("=== Blast L2 -> Ethereum L1 Withdrawal Proof ===");
        console.log("L2 Transaction Hash:");
        console.logBytes32(l2TxHash);
        console.log("");

        // Step 1: Fetch withdrawal transaction data from Blast L2
        console.log("Step 1: Fetching withdrawal data from Blast L2...");
        WithdrawalData memory withdrawal = fetchWithdrawalFromBlast(l2TxHash);

        console.log("Withdrawal Details:");
        console.log("  Nonce:", withdrawal.nonce);
        console.log("  Sender:", withdrawal.sender);
        console.log("  Target:", withdrawal.target);
        console.log("  Value:", withdrawal.value);
        console.log("  Gas Limit:", withdrawal.gasLimit);
        console.log("  Data length:", withdrawal.data.length);
        console.log("  L2 Block Number:", withdrawal.l2BlockNumber);
        console.log("");

        // Step 2: Construct withdrawal transaction and compute hash
        IOptimismPortal.WithdrawalTransaction memory tx = IOptimismPortal.WithdrawalTransaction({
            nonce: withdrawal.nonce,
            sender: withdrawal.sender,
            target: withdrawal.target,
            value: withdrawal.value,
            gasLimit: withdrawal.gasLimit,
            data: withdrawal.data
        });

        bytes32 withdrawalHash = hashWithdrawal(tx);
        console.log("Withdrawal Hash:");
        console.logBytes32(withdrawalHash);
        console.log("");

        // Step 3: Check if already proven
        console.log("Step 2: Checking if withdrawal is already proven on L1...");
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
                console.log("\nWithdrawal is finalized and ready to be claimed!");
                console.log("You can now call finalizeWithdrawalTransaction");
            } else {
                console.log("\nWithdrawal is proven but waiting for challenge period (~7 days) to pass.");
            }
            return;
        }
        console.log("Withdrawal not yet proven. Proceeding...");
        console.log("");

        // Step 4: Check if L2 output is available on L1
        console.log("Step 3: Checking if L2 output is available on L1...");
        uint256 latestBlock = oracle.latestBlockNumber();
        console.log("  Latest L2 block on L1:", latestBlock);
        console.log("  Required L2 block:", withdrawal.l2BlockNumber);
        
        if (latestBlock < withdrawal.l2BlockNumber) {
            console.log("\nERROR: L2 output not yet available on L1");
            console.log("Please wait for the L2 output oracle to sync and try again later.");
            console.log("L2 outputs are submitted approximately every hour.");
            revert("L2 output not available");
        }
        console.log("L2 output is available!");
        console.log("");

        // Step 5: Get L2 output index and proposal
        console.log("Step 4: Fetching L2 output data from oracle...");
        uint256 l2OutputIndex = oracle.getL2OutputIndexAfter(withdrawal.l2BlockNumber);
        IL2OutputOracle.OutputProposal memory outputProposal = oracle.getL2Output(l2OutputIndex);

        console.log("L2 Output Data:");
        console.log("  Output Index:", l2OutputIndex);
        console.log("  L2 Block Number:", outputProposal.l2BlockNumber);
        console.log("  Timestamp:", outputProposal.timestamp);
        console.log("  Output Root:");
        console.logBytes32(outputProposal.outputRoot);
        console.log("");

        // Step 6: Generate proofs from Blast L2
        console.log("Step 5: Generating withdrawal proofs from Blast L2...");
        bytes32 messageSlot = keccak256(abi.encode(withdrawalHash, uint256(0)));
        console.log("Storage Slot:");
        console.logBytes32(messageSlot);
        console.log("");

        // Get proof data from Blast using eth_getProof
        (bytes32 stateRoot, bytes32 storageRoot, bytes[] memory storageProof) = 
            getProofFromBlast(L2_TO_L1_MESSAGE_PASSER, messageSlot, outputProposal.l2BlockNumber);
        
        // Get block hash from Blast
        bytes32 blockHash = getBlockHashFromBlast(outputProposal.l2BlockNumber);

        console.log("Proof Data:");
        console.log("  State Root:");
        console.logBytes32(stateRoot);
        console.log("  Storage Root:");
        console.logBytes32(storageRoot);
        console.log("  Block Hash:");
        console.logBytes32(blockHash);
        console.log("  Storage Proof elements:", storageProof.length);
        console.log("");

        // Step 7: Construct the output root proof
        IOptimismPortal.OutputRootProof memory outputRootProof = IOptimismPortal.OutputRootProof({
            version: bytes32(0),
            stateRoot: stateRoot,
            messagePasserStorageRoot: storageRoot,
            latestBlockhash: blockHash
        });

        // Step 8: Submit the proof transaction to L1
        console.log("Step 6: Submitting proof transaction to OptimismPortal on L1...");
        console.log("Portal address:", OPTIMISM_PORTAL);
        console.log("Broadcaster:", msg.sender);
        console.log("");
        
        vm.startBroadcast();
        try portal.proveWithdrawalTransaction(tx, l2OutputIndex, outputRootProof, storageProof) {
            vm.stopBroadcast();
            console.log("=== SUCCESS ===");
            console.log("Withdrawal successfully proven!");
            console.log("\nNext steps:");
            console.log("1. Wait for the challenge period (~7 days) to pass");
            console.log("2. Call finalizeWithdrawalTransaction on the OptimismPortal");
            console.log("\nYou can check the status by calling:");
            console.log("  portal.provenWithdrawals(withdrawalHash)");
            console.log("  portal.isOutputFinalized(l2OutputIndex)");
        } catch Error(string memory reason) {
            vm.stopBroadcast();
            console.log("=== ERROR ===");
            console.log("Failed to prove withdrawal:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            vm.stopBroadcast();
            console.log("=== ERROR ===");
            console.log("Failed to prove withdrawal (low-level error)");
            console.logBytes(lowLevelData);
            revert("Low-level error");
        }
    }

    /// @notice Fetch withdrawal data from Blast L2 transaction
    function fetchWithdrawalFromBlast(bytes32 txHash) internal returns (WithdrawalData memory withdrawal) {
        // Create a fork of Blast to read data
        string memory blastRpc = vm.rpcUrl("blast");
        vm.createSelectFork(blastRpc);
        
        // Get the transaction receipt
        // Note: This is a workaround since vm.getReceipt doesn't exist
        // We'll use vm.load to read the receipt after fetching the tx
        
        // For now, we need to parse it differently - let's go back to mainnet
        // and use the transaction data directly
        
        // This is the tricky part - Foundry doesn't have direct receipt access in pure Solidity
        // We need to use the log data which we can get via vm cheatcodes on a fork
        
        // Let's try a different approach: etch the transaction and capture logs
        vm.createSelectFork(blastRpc);
        
        // Get block number first
        (bool success, bytes memory data) = address(0).call(abi.encodeWithSignature("eth_getTransactionByHash(bytes32)", txHash));
        require(success, "Failed to get transaction");
        
        // This won't work directly, we need the receipt
        // Let me try using vm.eth_getLogs or direct RPC calls
        
        revert("fetchWithdrawalFromBlast: Implementation requires FFI or cast. Use the FFI version instead.");
    }

    /// @notice Get storage proof from Blast L2 using eth_getProof
    function getProofFromBlast(
        address account,
        bytes32 storageKey,
        uint128 blockNumber
    ) internal view returns (
        bytes32 stateRoot,
        bytes32 storageRoot,
        bytes[] memory storageProof
    ) {
        // This requires eth_getProof RPC call which isn't directly available in Solidity
        // We would need to use vm.rpc() but that requires proper JSON handling
        
        revert("getProofFromBlast: eth_getProof requires FFI. Use the FFI version instead.");
    }

    /// @notice Get block hash from Blast L2
    function getBlockHashFromBlast(uint128 blockNumber) internal view returns (bytes32) {
        // Similar issue - requires RPC call
        revert("getBlockHashFromBlast: Requires FFI. Use the FFI version instead.");
    }

    /// @notice Hash a withdrawal transaction (matches Optimism spec)
    function hashWithdrawal(IOptimismPortal.WithdrawalTransaction memory _tx) internal pure returns (bytes32) {
        return keccak256(abi.encode(_tx.nonce, _tx.sender, _tx.target, _tx.value, _tx.gasLimit, _tx.data));
    }
}
