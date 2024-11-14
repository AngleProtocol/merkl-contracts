// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

contract JsonReader is Script {
    using stdJson for string;

    error FileNotFound(string path);
    error ValueNotFound(string path, string key);
    error ChainNotSupported(uint256 chainId);

    // Mapping of chain IDs to their names
    mapping(uint256 => string) internal chainNames;

    constructor() {
        // Mainnet and testnets
        chainNames[1] = "mainnet";
        chainNames[5] = "goerli";
        chainNames[11155111] = "sepolia";

        chainNames[10] = "optimism";
        chainNames[42161] = "arbitrum";
        chainNames[137] = "polygon";
        chainNames[42220] = "celo";
        chainNames[43114] = "avalanche";
        chainNames[250] = "fantom";
        chainNames[1313161554] = "aurora";
        chainNames[56] = "bsc";
        chainNames[100] = "gnosis";
        chainNames[1101] = "polygonzkevm";
        chainNames[8453] = "base";
        chainNames[42170] = "bob";
        chainNames[59144] = "linea";
        chainNames[324] = "zksync";
        chainNames[5000] = "mantle";
        chainNames[314] = "filecoin";
        chainNames[81457] = "blast";
        chainNames[34443] = "mode";
        chainNames[108] = "thundercore";
        chainNames[1116] = "coredao";
        chainNames[204] = "xlayer";
        chainNames[167008] = "taiko";
        chainNames[122] = "fuse";
        chainNames[13371] = "immutable";
        chainNames[534352] = "scroll";
        chainNames[169] = "manta";
        chainNames[713100] = "sei";
        chainNames[2000] = "fraxtal";
        chainNames[592] = "astar";
        chainNames[6038361] = "astarzkevm";
        chainNames[30] = "rootstock";
        chainNames[1284] = "moonbeam";
        chainNames[1273227453] = "skale";
        chainNames[59140] = "worldchain";
    }

    /// @notice Gets the network-specific config path
    /// @param chainId The chain ID
    /// @return The full path to the network config file
    function getNetworkPath(uint256 chainId) public view returns (string memory) {
        string memory chainName = chainNames[chainId];
        if (bytes(chainName).length == 0) revert ChainNotSupported(chainId);

        string memory root = vm.projectRoot();
        return string.concat(root, "/deploy/networks/", chainName, ".json");
    }

    /// @notice Reads an address value from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The address value
    function readAddress(uint256 chainId, string memory key) public view returns (address) {
        string memory path = getNetworkPath(chainId);
        return readAddressFromPath(path, key);
    }

    /// @notice Reads a string value from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The string value
    function readString(uint256 chainId, string memory key) public view returns (string memory) {
        string memory path = getNetworkPath(chainId);
        return readStringFromPath(path, key);
    }

    /// @notice Reads a uint256 value from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The uint256 value
    function readUint(uint256 chainId, string memory key) public view returns (uint256) {
        string memory path = getNetworkPath(chainId);
        return readUintFromPath(path, key);
    }

    /// @notice Reads a string array from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The string array
    function readStringArray(uint256 chainId, string memory key) public view returns (string[] memory) {
        string memory path = getNetworkPath(chainId);
        return readStringArrayFromPath(path, key);
    }

    // Direct path reading functions
    function readAddressFromPath(string memory path, string memory key) public view returns (address) {
        string memory json = readJsonFile(path);
        bytes memory raw = json.parseRaw(string.concat(".", key));
        if (raw.length == 0) revert ValueNotFound(path, key);
        return bytesToAddress(raw);
    }

    function readStringFromPath(string memory path, string memory key) public view returns (string memory) {
        string memory json = readJsonFile(path);
        bytes memory raw = json.parseRaw(string.concat(".", key));
        if (raw.length == 0) revert ValueNotFound(path, key);
        return string(raw);
    }

    function readUintFromPath(string memory path, string memory key) public view returns (uint256) {
        string memory json = readJsonFile(path);
        bytes memory raw = json.parseRaw(string.concat(".", key));
        if (raw.length == 0) revert ValueNotFound(path, key);
        return abi.decode(raw, (uint256));
    }

    function readStringArrayFromPath(string memory path, string memory key) public view returns (string[] memory) {
        string memory json = readJsonFile(path);
        bytes memory raw = json.parseRaw(string.concat(".", key));
        if (raw.length == 0) revert ValueNotFound(path, key);
        return abi.decode(raw, (string[]));
    }

    /// @notice Reads a JSON file from the given path
    /// @param path The path to the JSON file
    /// @return The JSON content as a string
    function readJsonFile(string memory path) public view returns (string memory) {
        try vm.readFile(path) returns (string memory json) {
            return json;
        } catch {
            revert FileNotFound(path);
        }
    }

    /// @notice Utility function to convert bytes to address
    /// @param bys Bytes to convert
    /// @return addr Resulting address
    function bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 32))
        }
    }
}
