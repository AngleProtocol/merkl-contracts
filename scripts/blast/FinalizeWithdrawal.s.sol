// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";

/// @notice Optimism Portal interface for finalizing withdrawals
interface IOptimismPortal {
    struct WithdrawalTransaction {
        uint256 nonce;
        address sender;
        address target;
        uint256 value;
        uint256 gasLimit;
        bytes data;
    }

    function finalizeWithdrawalTransaction(WithdrawalTransaction memory _tx) external;

    function provenWithdrawals(bytes32 withdrawalHash) external view returns (bytes32 outputRoot, uint128 timestamp, uint128 l2OutputIndex);

    function finalizedWithdrawals(bytes32 withdrawalHash) external view returns (bool);

    function FINALIZATION_PERIOD_SECONDS() external view returns (uint256);
}

/// @notice L2OutputOracle interface for checking output finalization
interface IL2OutputOracle {
    struct OutputProposal {
        bytes32 outputRoot;
        uint128 timestamp;
        uint128 l2BlockNumber;
    }

    function getL2Output(uint256 _l2OutputIndex) external view returns (OutputProposal memory);
}

/// @title FinalizeBlastWithdrawal
/// @notice Foundry script to finalize a withdrawal transaction from Blast L2 on Ethereum L1
/// @author Angle Labs
/// @dev This is step 3 of the withdrawal process (after the 7-day challenge period)
///
/// Usage:
///   forge script scripts/blast/FinalizeWithdrawal.s.sol:FinalizeBlastWithdrawal \
///     --sig "run(bytes32)" <L2_TX_HASH> \
///     --rpc-url mainnet \
///     --broadcast
contract FinalizeBlastWithdrawal is Script {
    using stdJson for string;

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

    /// @notice Main function to finalize a withdrawal
    /// @param l2TxHash The transaction hash on Blast L2
    /// Example: 0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1
    function run(bytes32 l2TxHash) public {
        console.log("=== Finalizing Blast L2 Withdrawal ===");
        console.log("L2 Transaction Hash:", vm.toString(l2TxHash));
        console.log("");

        // Step 1: Fetch withdrawal transaction data from L2
        console.log("Step 1: Fetching withdrawal data from Blast L2...");
        WithdrawalData memory withdrawal = fetchWithdrawalData(l2TxHash);

        console.log("  Nonce:", withdrawal.nonce);
        console.log("  Sender:", withdrawal.sender);
        console.log("  Target:", withdrawal.target);
        console.log("  Value:", withdrawal.value);
        console.log("  Gas Limit:", withdrawal.gasLimit);
        console.log("  Data length:", withdrawal.data.length);
        console.log("  L2 Block Number:", withdrawal.l2BlockNumber);
        console.log("");

        // Step 2: Compute withdrawal hash
        bytes32 withdrawalHash = hashWithdrawal(withdrawal);
        console.log("Step 2: Withdrawal hash computed");
        console.log("  Hash:", vm.toString(withdrawalHash));
        console.log("");

        // Step 3: Check if already finalized
        console.log("Step 3: Checking finalization status...");
        bool isFinalized = portal.finalizedWithdrawals(withdrawalHash);

        if (isFinalized) {
            console.log("  Status: ALREADY FINALIZED");
            console.log("");
            console.log("This withdrawal has already been finalized. No action needed.");
            return;
        }

        console.log("  Status: Not yet finalized");
        console.log("");

        // Step 4: Check if proven
        console.log("Step 4: Checking proof status...");
        (bytes32 outputRoot, uint128 proofTimestamp, uint128 l2OutputIndex) = portal.provenWithdrawals(withdrawalHash);

        if (outputRoot == bytes32(0)) {
            console.log("  Status: NOT PROVEN");
            console.log("");
            console.log("ERROR: This withdrawal has not been proven yet!");
            console.log("You must run ProveWithdrawal.s.sol first.");
            revert("Withdrawal not proven");
        }

        console.log("  Status: Proven");
        console.log("  Output Root:", vm.toString(outputRoot));
        console.log("  Proof Timestamp:", proofTimestamp);
        console.log("  L2 Output Index:", l2OutputIndex);
        console.log("");

        // Step 5: Check if challenge period has passed
        console.log("Step 5: Checking challenge period...");
        uint256 finalizationPeriod = portal.FINALIZATION_PERIOD_SECONDS();
        uint256 currentTime = block.timestamp;
        uint256 canFinalizeAt = proofTimestamp + finalizationPeriod;

        console.log("  Finalization Period:", finalizationPeriod, "seconds");
        console.log("  Proof Timestamp:", proofTimestamp);
        console.log("  Current Time:", currentTime);
        console.log("  Can Finalize At:", canFinalizeAt);

        if (currentTime < canFinalizeAt) {
            uint256 timeRemaining = canFinalizeAt - currentTime;
            console.log("  Status: WAITING");
            console.log("");
            console.log("ERROR: Challenge period has not passed yet!");
            console.log("Time remaining:", timeRemaining, "seconds");
            console.log("Time remaining:", timeRemaining / 3600, "hours");
            console.log("Time remaining:", timeRemaining / 86400, "days");
            revert("Challenge period not passed");
        }

        console.log("  Status: Ready to finalize");
        console.log("");

        // Step 6: Finalize the withdrawal
        console.log("Step 6: Finalizing withdrawal transaction...");

        IOptimismPortal.WithdrawalTransaction memory tx = IOptimismPortal.WithdrawalTransaction({
            nonce: withdrawal.nonce,
            sender: withdrawal.sender,
            target: withdrawal.target,
            value: withdrawal.value,
            gasLimit: withdrawal.gasLimit,
            data: withdrawal.data
        });

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        console.log("  Calling finalizeWithdrawalTransaction...");
        portal.finalizeWithdrawalTransaction(tx);

        vm.stopBroadcast();

        console.log("  Status: SUCCESS");
        console.log("");
        console.log("=== Withdrawal Finalized Successfully! ===");
        console.log("");
        console.log("The withdrawal has been completed and funds should now be available on L1.");
    }

    /// @notice Fetch withdrawal transaction data from Blast L2
    function fetchWithdrawalData(bytes32 l2TxHash) internal returns (WithdrawalData memory withdrawal) {
        string memory l2RpcUrl = vm.envOr("ETH_NODE_URI_81457", string("https://rpc.blast.io"));

        // Fetch transaction receipt
        string[] memory inputs = new string[](5);
        inputs[0] = "cast";
        inputs[1] = "receipt";
        inputs[2] = vm.toString(l2TxHash);
        inputs[3] = "--json";
        inputs[4] = string.concat("--rpc-url=", l2RpcUrl);

        string memory receiptJson = string(vm.ffi(inputs));

        // Parse block number
        withdrawal.l2BlockNumber = vm.parseJsonUint(receiptJson, ".blockNumber");

        // Parse logs to find MessagePassed event
        string memory logsJson = string(vm.parseJson(receiptJson, ".logs"));

        // Try each log index until we find the MessagePassed event
        for (uint256 i = 0; i < 20; i++) {
            if (_tryParseLog(logsJson, i, withdrawal)) {
                return withdrawal;
            }
        }

        revert("MessagePassed event not found in transaction");
    }

    /// @notice Try to parse a log at a specific index
    function _tryParseLog(string memory logsJson, uint256 i, WithdrawalData memory withdrawal) internal returns (bool) {
        try vm.parseJsonAddress(logsJson, string.concat(".[", vm.toString(i), "].address")) returns (address logAddress) {
            if (logAddress != L2_TO_L1_MESSAGE_PASSER) return false;

            bytes memory topicsData = vm.parseJson(logsJson, string.concat(".[", vm.toString(i), "].topics"));
            bytes32[] memory topics = abi.decode(topicsData, (bytes32[]));

            if (topics.length > 0 && topics[0] == MESSAGE_PASSED_EVENT) {
                bytes memory logData = vm.parseJsonBytes(logsJson, string.concat(".[", vm.toString(i), "].data"));

                withdrawal.nonce = uint256(topics[1]);
                withdrawal.sender = address(uint160(uint256(topics[2])));
                withdrawal.target = address(uint160(uint256(topics[3])));

                (withdrawal.value, withdrawal.gasLimit, withdrawal.data, ) = abi.decode(logData, (uint256, uint256, bytes, bytes32));

                return true;
            }
        } catch {
            // No more logs or parse error
        }
        return false;
    }

    /// @notice Compute the withdrawal hash
    function hashWithdrawal(WithdrawalData memory withdrawal) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(withdrawal.nonce, withdrawal.sender, withdrawal.target, withdrawal.value, withdrawal.gasLimit, withdrawal.data)
            );
    }
}
