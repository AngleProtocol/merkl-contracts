// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

// Base contract with shared utilities
contract MockTokenScript is BaseScript {}

// Deploy script
contract Deploy is MockTokenScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN PARAMETERS
        string memory name = "Mock Token";
        string memory symbol = "MOCK";
        uint8 decimals = 18;
        _run(name, symbol, decimals);
    }

    function run(string calldata name, string calldata symbol, uint8 decimals) external broadcast {
        _run(name, symbol, decimals);
    }

    function _run(string memory name, string memory symbol, uint8 decimals) internal {
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
    function run() external broadcast {
        // forge script scripts/MockToken.s.sol:Mint --rpc-url ronin --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast -i 1
        address token = 0x152Ce4c126b91EdE48c5C13E3aF299465800E9E8;
        address recipient = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        uint256 amount = 1e18;
        _run(token, recipient, amount);
    }

    function run(address token, address recipient, uint256 amount) external broadcast {
        _run(token, recipient, amount);
    }

    function _run(address token, address recipient, uint256 amount) internal {
        MockToken(token).mint(recipient, amount);
        console.log("Minted %s tokens to %s", amount, recipient);
        console.log(MockToken(token).name());
        console.log(MockToken(token).symbol());
        console.log(MockToken(token).decimals());
    }
}

// Approve script
contract Approve is MockTokenScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED APPROVAL PARAMETERS
        address token = address(0);
        address spender = address(0);
        uint256 amount = 0;
        _run(token, spender, amount);
    }

    function run(address token, address spender, uint256 amount) external broadcast {
        _run(token, spender, amount);
    }

    function _run(address token, address spender, uint256 amount) internal {
        MockToken(token).approve(spender, amount);
        console.log("Approved %s tokens to spender %s", amount, spender);
    }
}

// Transfer script
contract Transfer is MockTokenScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED TRANSFER PARAMETERS
        address token = address(0);
        address recipient = address(0);
        uint256 amount = 0;
        _run(token, recipient, amount);
    }

    function run(address token, address recipient, uint256 amount) external broadcast {
        _run(token, recipient, amount);
    }

    function _run(address token, address recipient, uint256 amount) internal {
        MockToken(token).transfer(recipient, amount);
        console.log("Transferred %s tokens to %s", amount, recipient);
    }
}

// BatchMint script
contract BatchMint is MockTokenScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED BATCH MINT PARAMETERS
        address token = address(0);
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        _run(token, recipients, amounts);
    }

    function run(address token, address[] calldata recipients, uint256[] calldata amounts) external broadcast {
        _run(token, recipients, amounts);
    }

    function _run(address token, address[] memory recipients, uint256[] memory amounts) internal {
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
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED BATCH TRANSFER PARAMETERS
        address token = address(0);
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        _run(token, recipients, amounts);
    }

    function run(address token, address[] calldata recipients, uint256[] calldata amounts) external broadcast {
        _run(token, recipients, amounts);
    }

    function _run(address token, address[] memory recipients, uint256[] memory amounts) internal {
        require(recipients.length == amounts.length, "Length mismatch");

        MockToken mockToken = MockToken(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            mockToken.transfer(recipients[i], amounts[i]);
            console.log("Transferred %s tokens to %s", amounts[i], recipients[i]);
        }
    }
}
