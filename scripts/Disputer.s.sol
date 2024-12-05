// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { JsonReader } from "./utils/JsonReader.sol";
import { Disputer } from "../contracts/Disputer.sol";
import { Distributor } from "../contracts/Distributor.sol";

// Base contract with shared constants and utilities
contract DisputerScript is BaseScript, JsonReader {
    address[] public DISPUTER_WHITELIST = [
        0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e,
        0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B,
        0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA
    ];
}

// Deploy scrip
contract Deploy is DisputerScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Read configuration from JSON
        address angleLabs = readAddress(chainId, "AngleLabs");
        address distributor = readAddress(chainId, "Merkl.Distributor");

        address disputer = address(
            new Disputer{ salt: vm.envBytes32("DEPLOY_SALT") }(
                broadcaster,
                DISPUTER_WHITELIST,
                Distributor(distributor)
            )
        );
        Disputer(disputer).transferOwnership(angleLabs);

        console.log("Disputer deployed at:", disputer);
    }
}

// SetDistributor scrip
contract SetDistributor is DisputerScript {
    function run(Distributor newDistributor) external {
        _run(newDistributor);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED DISTRIBUTOR ADDRESS
        address distributorAddress = address(0);
        _run(Distributor(distributorAddress));
    }

    function _run(Distributor _newDistributor) internal broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");

        Disputer(disputerAddress).setDistributor(_newDistributor);

        console.log("Distributor updated to:", address(_newDistributor));
    }
}

// AddToWhitelist scrip
contract AddToWhitelist is DisputerScript {
    function run(address account) external {
        _run(account);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE ACCOUNT TO WHITELIST
        address account = address(0);
        _run(account);
    }

    function _run(address _account) internal broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");

        Disputer(disputerAddress).addToWhitelist(_account);

        console.log("Address added to whitelist:", _account);
    }
}

// RemoveFromWhitelist scrip
contract RemoveFromWhitelist is DisputerScript {
    function run(address account) external {
        _run(account);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE ACCOUNT TO REMOVE FROM WHITELIST
        address accountToRemove = address(0);
        _run(accountToRemove);
    }

    function _run(address _account) internal broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");

        Disputer(disputerAddress).removeFromWhitelist(_account);
        console.log("Address removed from whitelist:", _account);
    }
}

// FundDisputerWhitelist script
contract FundDisputerWhitelist is DisputerScript {
    function run(uint256 amountToFund) external {
        _run(amountToFund);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE FUNDING AMOUNT (in ether)
        uint256 amountToFund = 0.001 ether;
        _run(amountToFund);
    }

    function _run(uint256 _amountToFund) internal broadcast {
        console.log("Chain ID:", block.chainid);

        // Fund each whitelisted address
        for (uint256 i = 0; i < DISPUTER_WHITELIST.length; i++) {
            address recipient = DISPUTER_WHITELIST[i];
            console.log("Funding whitelist address:", recipient);

            // Transfer native token
            (bool success, ) = recipient.call{ value: _amountToFund }("");
            require(success, "Transfer failed");

            console.log("Funded with amount:", _amountToFund);
        }

        // Print summary
        console.log("\n=== Funding Summary ===");
        console.log("Amount per address:", _amountToFund);
        console.log("Number of addresses funded:", DISPUTER_WHITELIST.length);
    }
}

contract FundDisputer is DisputerScript {
    function run(uint256 amountToFund) external {
        _run(amountToFund);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE FUNDING AMOUNT (in dispute tokens decimals)
        uint256 amountToFund = 100 * 10 ** 6; // i.e. 100 USDC -> 100 * 10 ** 6
        _run(amountToFund);
    }

    function _run(uint256 _amountToFund) internal broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");

        IERC20 disputeToken = Disputer(disputerAddress).distributor().disputeToken();
        console.log("Transferring %s to %s", _amountToFund, disputerAddress);
        disputeToken.transfer(disputerAddress, _amountToFund);
    }
}

contract WithdrawFunds is DisputerScript {
    function run() external {
        // MODIFY THESE VALUES TO SET THE WITHDRAWAL PARAMETERS
        address asset = address(0); // Use address(0) for ETH, or token address for ERC20
        uint256 amountToWithdraw = 100 * 10 ** 6; // Adjust decimals according to asset
        address recipient = address(0); // Set the recipient address
        _run(asset, recipient, amountToWithdraw);
    }

    function run(address asset, address recipient, uint256 amountToWithdraw) external {
        _run(asset, recipient, amountToWithdraw);
    }

    function _run(address asset, address to, uint256 _amountToWithdraw) internal broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");
        Disputer disputer = Disputer(disputerAddress);

        if (asset == address(0)) {
            // Withdraw ETH
            disputer.withdrawFunds(payable(to), _amountToWithdraw);
            console.log("Withdrew %s ETH to %s", _amountToWithdraw, to);
        } else {
            // Withdraw ERC20 token
            disputer.withdrawFunds(asset, to, _amountToWithdraw);
            console.log("Withdrew %s %s to %s", _amountToWithdraw, asset, to);
        }
    }
}
