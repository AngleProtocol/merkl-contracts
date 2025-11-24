// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { PointToken } from "../contracts/partners/tokenWrappers/PointToken.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";

// Base contract with shared constants and utilities
contract PointTokenScript is BaseScript {
    // Common constants and utilities for PointToken scripts
}

// Deploy script
contract DeployPointToken is PointTokenScript {
    function run() external broadcast {
        // forge script scripts/PointToken.s.sol:DeployPointToken --rpc-url arbitrum --broadcast --verify -vvvv
        uint256 chainId = block.chainid;
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN PARAMETERS
        string memory name = "Stable Tracking";
        string memory symbol = "stbl-tracking";
        address minter = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        uint256 amount = 10_000_000_000 * 1e18;
        address creator = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        uint8 decimals = 18;

        address accessControlManager = address(DistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd).accessControlManager());
        _run(name, symbol, minter, accessControlManager, amount, creator);
    }

    function _run(
        string memory name,
        string memory symbol,
        address minter,
        address accessControlManager,
        uint256 amount,
        address creator
    ) internal {
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Deploy PointToken
        PointToken token = new PointToken(name, symbol, minter, accessControlManager);

        // Load the point token contract
        // PointToken token = PointToken(0xf9e03FfE6d23D37199CC4B29Dbe0224d8735d02C);
        console.log("Point token deployed at:", address(token));
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Decimals:", token.decimals());

        // Mint initial supply to deployer
        token.mint(minter, amount);

        // Whitelist the minter
        token.toggleWhitelistedRecipient(minter);
        console.log("Initial supply minted to deployer");

        // Whitelist the Merkl Contracts
        token.toggleWhitelistedRecipient(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);
        token.toggleWhitelistedRecipient(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
        token.toggleWhitelistedRecipient(0xeaC6A75e19beB1283352d24c0311De865a867DAB);
        token.toggleWhitelistedRecipient(0x1A2039792b43C150d3bE02135978A5c3f4d874F4);
        token.transfer(0x1A2039792b43C150d3bE02135978A5c3f4d874F4, 1e10 * 1e18);

        console.log("Whitelisted recipients:");
        // transfer to the SAFE
        if (creator != minter) {
            console.log("Transferring initial supply to KAT SAFE:", creator);
            token.transfer(creator, amount);
        }

        console.log("Transferred initial supply to KAT SAFE");
    }
}

contract MintMorePointToken is PointTokenScript {
    // forge script scripts/PointToken.s.sol:MintMorePointToken --rpc-url hyperevm --broadcast --verify -vvvv
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address recipient = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        address pointToken = 0x076C42Fe8E13253133738cC8674d85135137270D;
        _run(recipient, pointToken);
    }

    function _run(address recipient, address pointToken) internal {
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Deploy PointToken
        PointToken token = PointToken(pointToken);

        // Mint initial supply to deployer
        token.mint(recipient, 1e12 * 1e18);
        console.log("Initial supply minted to deployer");
    }
}

contract WhitelistRecipient is PointTokenScript {
    // forge script scripts/PointToken.s.sol:WhitelistRecipient --rpc-url hyperevm --broadcast --verify -vvvv
    function run() external broadcast {
        uint256 chainId = block.chainid;
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN PARAMETERS
        address recipient = 0xABb29f9CCd2dD058A2DA6b6022f82F90Ae0CEc90;
        address pointToken = 0x49c7B39A2E01869d39548F232F9B1586DA8Ef9c2;
        _run(recipient, pointToken);
    }

    function _run(address recipient, address pointToken) internal {
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Deploy PointToken
        PointToken token = PointToken(pointToken);

        // Mint initial supply to deployer
        token.toggleWhitelistedRecipient(recipient);
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

    function _run(address[] memory _accounts, uint256[] memory _amounts, address _pointTokenAddress) internal broadcast {
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
