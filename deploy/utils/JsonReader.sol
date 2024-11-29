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

    /// @notice Gets the network-specific config path
    /// @return The full path to the network config file
    function getPath() public view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/node_modules/@angleprotocol/sdk/dist/src/registry/registry.json");
    }

    /// @notice Reads an address value from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The address value
    function readAddress(uint256 chainId, string memory key) public view returns (address) {
        string memory path = getPath();
        return readAddressFromPath(path, string.concat(vm.toString(chainId), ".", key));
    }

    /// @notice Reads a string value from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The string value
    function readString(uint256 chainId, string memory key) public view returns (string memory) {
        string memory path = getPath();
        return readStringFromPath(path, string.concat(vm.toString(chainId), ".", key));
    }

    /// @notice Reads a uint256 value from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The uint256 value
    function readUint(uint256 chainId, string memory key) public view returns (uint256) {
        string memory path = getPath();
        return readUintFromPath(path, string.concat(vm.toString(chainId), ".", key));
    }

    /// @notice Reads a string array from the network's JSON file
    /// @param chainId The chain ID
    /// @param key The JSON key to read
    /// @return The string array
    function readStringArray(uint256 chainId, string memory key) public view returns (string[] memory) {
        string memory path = getPath();
        return readStringArrayFromPath(path, string.concat(vm.toString(chainId), ".", key));
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
