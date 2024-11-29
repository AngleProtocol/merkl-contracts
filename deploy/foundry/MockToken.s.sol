// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "../utils/Base.s.sol";
import { MockToken } from "../../contracts/mock/MockToken.sol";
import { JsonReader } from "../utils/JsonReader.sol";

// Base contract with shared utilities
contract MockTokenScript is BaseScript, JsonReader {}

// Deploy script
contract Deploy is MockTokenScript {
    function run(string calldata name, string calldata symbol, uint8 decimals) external broadcast {
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Deploy MockToken
        MockToken token = new MockToken(name, symbol, decimals);
        console.log("MockToken deployed at:", address(token));
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Decimals:", decimals);

        // Mint initial supply to deployer
        token.mint(broadcaster, 1_000_000_000_000_000_000_000_000_000);
        console.log("Initial supply minted to deployer");
    }
}

// Mint script
contract Mint is MockTokenScript {
    function run(address token, address recipient, uint256 amount) external broadcast {
        MockToken(token).mint(recipient, amount);
        console.log("Minted %s tokens to %s", amount, recipient);
    }
}

// Approve script
contract Approve is MockTokenScript {
    function run(address token, address spender, uint256 amount) external broadcast {
        MockToken(token).approve(spender, amount);
        console.log("Approved %s tokens to spender %s", amount, spender);
    }
}

// Transfer script
contract Transfer is MockTokenScript {
    function run(address token, address recipient, uint256 amount) external broadcast {
        MockToken(token).transfer(recipient, amount);
        console.log("Transferred %s tokens to %s", amount, recipient);
    }
}

// BatchMint script
contract BatchMint is MockTokenScript {
    function run(address token, address[] calldata recipients, uint256[] calldata amounts) external broadcast {
        require(recipients.length == amounts.length, "Length mismatch");

        MockToken mockToken = MockToken(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            mockToken.mint(recipients[i], amounts[i]);
            console.log("Minted %s tokens to %s", amounts[i], recipients[i]);
        }
    }
}

// BatchTransfer script
contract BatchTransfer is MockTokenScript {
    function run(address token, address[] calldata recipients, uint256[] calldata amounts) external broadcast {
        require(recipients.length == amounts.length, "Length mismatch");

        MockToken mockToken = MockToken(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            mockToken.transfer(recipients[i], amounts[i]);
            console.log("Transferred %s tokens to %s", amounts[i], recipients[i]);
        }
    }
}
