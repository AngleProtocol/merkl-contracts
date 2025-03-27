// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JsonReader } from "@utils/JsonReader.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { PointToken } from "../contracts/partners/tokenWrappers/PointToken.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";

// Base contract with shared constants and utilities
contract PointTokenScript is BaseScript, JsonReader {
    // Common constants and utilities for PointToken scripts
}

// Deploy script
contract DeployPointToken is PointTokenScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN PARAMETERS
        string memory name = "Turtle TAC Point";
        string memory symbol = "TACPOINT";
        address minter = broadcaster;
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
        token.mint(minter, 10e6 * 1e18);
        console.log("Initial supply minted to deployer");
    }
}

// ToggleMinter script
contract ToggleMinter is PointTokenScript {
    function run(address minter, address pointTokenAddress) external {
        _run(minter, pointTokenAddress);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE MINTER ADDRESS
        address minter = address(0);
        address pointTokenAddress = address(0);
        _run(minter, pointTokenAddress);
    }

    function _run(address _minter, address _pointTokenAddress) internal broadcast {
        uint256 chainId = block.chainid;

        PointToken(_pointTokenAddress).toggleMinter(_minter);

        console.log("Toggled minter status for:", _minter);
    }
}

// ToggleAllowedTransfers script
contract ToggleAllowedTransfers is PointTokenScript {
    function run(address pointTokenAddress) external {
        _run(pointTokenAddress);
    }

    function run() external {
        uint256 chainId = block.chainid;
        address pointTokenAddress = address(0);
        _run(pointTokenAddress);
    }

    function _run(address _pointTokenAddress) internal broadcast {
        PointToken(_pointTokenAddress).toggleAllowedTransfers();

        console.log("Toggled allowed transfers status");
    }
}

// ToggleWhitelistedRecipient script
contract ToggleWhitelistedRecipient is PointTokenScript {
    function run(address recipient, address pointTokenAddress) external {
        _run(recipient, pointTokenAddress);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE RECIPIENT ADDRESS
        address recipient = address(0);
        address pointTokenAddress = address(0);
        _run(recipient, pointTokenAddress);
    }

    function _run(address _recipient, address _pointTokenAddress) internal broadcast {
        uint256 chainId = block.chainid;

        PointToken(_pointTokenAddress).toggleWhitelistedRecipient(_recipient);

        console.log("Toggled whitelisted recipient status for:", _recipient);
    }
}

// Mint script
contract Mint is PointTokenScript {
    function run(address account, uint256 amount, address pointTokenAddress) external {
        _run(account, amount, pointTokenAddress);
    }

    function run() external {
        // MODIFY THESE VALUES TO SET THE RECIPIENT AND AMOUNT
        address account = address(0);
        uint256 amount = 1000 * 10 ** 18; // 1000 tokens with 18 decimals
        address pointTokenAddress = address(0);
        _run(account, amount, pointTokenAddress);
    }

    function _run(address _account, uint256 _amount, address _pointTokenAddress) internal broadcast {
        uint256 chainId = block.chainid;

        PointToken(_pointTokenAddress).mint(_account, _amount);

        console.log("Minted %s tokens to %s", _amount, _account);
    }
}

// MintBatch script
contract MintBatch is PointTokenScript {
    function run(address[] calldata accounts, uint256[] calldata amounts, address pointTokenAddress) external {
        _run(accounts, amounts, pointTokenAddress);
    }

    function run() external {
        // MODIFY THESE VALUES TO SET THE RECIPIENTS AND AMOUNTS
        address[] memory accounts = new address[](2);
        accounts[0] = address(0x1);
        accounts[1] = address(0x2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10 ** 18; // 1000 tokens
        amounts[1] = 2000 * 10 ** 18; // 2000 tokens

        address pointTokenAddress = address(0);

        _run(accounts, amounts, pointTokenAddress);
    }

    function _run(
        address[] memory _accounts,
        uint256[] memory _amounts,
        address _pointTokenAddress
    ) internal broadcast {
        require(_accounts.length == _amounts.length, "Arrays length mismatch");

        uint256 chainId = block.chainid;

        PointToken(_pointTokenAddress).mintBatch(_accounts, _amounts);

        console.log("Minted tokens in batch to %s accounts", _accounts.length);
    }
}

// Burn script
contract Burn is PointTokenScript {
    function run(address account, uint256 amount, address pointTokenAddress) external {
        _run(account, amount, pointTokenAddress);
    }

    function run() external {
        // MODIFY THESE VALUES TO SET THE ACCOUNT AND AMOUNT
        address account = address(0);
        uint256 amount = 1000 * 10 ** 18; // 1000 tokens with 18 decimals
        address pointTokenAddress = address(0);
        _run(account, amount, pointTokenAddress);
    }

    function _run(address _account, uint256 _amount, address _pointTokenAddress) internal broadcast {
        uint256 chainId = block.chainid;

        PointToken(_pointTokenAddress).burn(_account, _amount);

        console.log("Burned %s tokens from %s", _amount, _account);
    }
}
