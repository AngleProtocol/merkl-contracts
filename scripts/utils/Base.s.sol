// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <=0.9.0;

import { Script } from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Needed for the deterministic deployments.
    bytes32 internal constant ZERO_SALT = bytes32(0);

    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;

    /// @dev The private key of the transaction broadcaster.
    uint256 internal broadcasterPrivateKey;

    /// @dev Used to derive the broadcaster's address if $DEPLOYER_ADDRESS is not defined.
    string internal mnemonic;

    enum Operation {
        Call,
        DelegateCall
    }

    /// @dev Initializes the transaction broadcaster like this:
    ///
    /// - If $PRIVATE_KEY is defined, use it to set the broadcaster.
    /// - If $DEPLOYER_ADDRESS is defined, use it.
    /// - Otherwise, derive the broadcaster address from $MNEMONIC.
    /// - If $MNEMONIC is not defined, default to a test mnemonic.
    ///
    /// The use case for $PRIVATE_KEY or $DEPLOYER_ADDRESS is to specify the broadcaster key via environment variable or the command line respectively.
    constructor() {
        uint256 privateKey = vm.envOr({ name: "DEPLOYER_PRIVATE_KEY", defaultValue: uint256(0) });
        if (privateKey != 0) {
            broadcaster = vm.addr(privateKey);
            broadcasterPrivateKey = privateKey;
        } else {
            address from = vm.envOr({ name: "DEPLOYER_ADDRESS", defaultValue: address(0) });
            if (from != address(0)) {
                broadcaster = from;
            } else {
                mnemonic = vm.envOr({ name: "MNEMONIC", defaultValue: TEST_MNEMONIC });
                (broadcaster, ) = deriveRememberKey({ mnemonic: mnemonic, index: 0 });
            }
        }
    }

    modifier broadcast() {
        if (broadcasterPrivateKey != 0) {
            vm.startBroadcast(broadcasterPrivateKey);
        } else {
            vm.startBroadcast(broadcaster);
        }
        _;
        vm.stopBroadcast();
    }

    modifier fork(string memory network) {
        vm.createSelectFork(vm.rpcUrl(network));
        _;
    }

    function _serializeJson(
        uint256 chainId,
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        bytes memory additionalData
    ) internal {
        _serializeJson(chainId, to, value, data, operation, additionalData, address(0));
    }

    function _serializeJson(
        uint256 chainId,
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        bytes memory additionalData,
        address safe
    ) internal {
        string memory json = "";
        vm.serializeUint(json, "chainId", chainId);
        vm.serializeAddress(json, "to", to);
        vm.serializeUint(json, "value", value);
        vm.serializeUint(json, "operation", uint256(operation));
        vm.serializeBytes(json, "additionalData", additionalData);
        if (safe != address(0)) {
            vm.serializeAddress(json, "safe", safe);
        }
        string memory finalJson = vm.serializeBytes(json, "data", data);

        vm.writeJson(finalJson, string.concat("./transactions/", vm.toString(chainId), ".json"));
    }
}
