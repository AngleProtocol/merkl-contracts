// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JsonReader } from "@utils/JsonReader.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { PointToken } from "../contracts/partners/tokenWrappers/PointToken.sol";

// Base contract with shared utilities
contract PointTokenScript is BaseScript, JsonReader {}

// Deploy script
contract DeployPointToken is PointTokenScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN PARAMETERS
        string memory name = "Miles";
        string memory symbol = "Miles";
        address minter = 0xa9bbbDDe822789F123667044443dc7001fb43C01;
        uint8 decimals = 18;
        address accessControlManager = readAddress(chainId, "Merkl.CoreMerkl");
        _run(name, symbol, minter, accessControlManager);
    }

    function _run(string memory name, string memory symbol, address minter, address accessControlManager) internal {
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Deploy PointToken
        PointToken token = new PointToken(name, symbol, minter, accessControlManager);
        console.log("Point token deployed at:", address(token));
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Decimals:", token.decimals());

        // Mint initial supply to deployer
        token.mint(minter, 1e6 * 1e18);
        console.log("Initial supply minted to deployer");
    }
}
