// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { BaseScript } from "../utils/Base.s.sol";

// NOTE: This script is used to fund the whitelist of disputers for a given chain.
// Can be executed with (0.1 ether = 100000000000000000 wei):
// forge script deploy/foundry/fundDisputerWhitelist.s.sol:FundDisputerWhitelistScript \
//     -vvvv \
//     --rpc-url localhost \
//     --sig "run(uint256,address[])" \
//     100000000000000000 "[0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e,0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B,0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA]"
contract FundDisputerWhitelistScript is BaseScript {
    function run(uint256 fundAmount, address[] calldata whitelist) external broadcast {
        console.log("Chain ID:", block.chainid);

        // Fund each whitelisted address
        for (uint256 i = 0; i < whitelist.length; i++) {
            address recipient = whitelist[i];
            console.log("Funding whitelist address:", recipient);

            // Transfer native token
            (bool success, ) = recipient.call{ value: fundAmount }("");
            require(success, "Transfer failed");

            console.log("Funded with amount:", fundAmount);
        }

        // Print summary
        console.log("\n=== Funding Summary ===");
        console.log("Amount per address:", fundAmount);
        console.log("Number of addresses funded:", whitelist.length);
    }
}
