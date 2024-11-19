// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";

import { BaseScript } from "../utils/Base.s.sol";
import { MockToken } from "../../contracts/mock/MockToken.sol";

///NOTE: This script is used to mint AGLA tokens to a list of recipients.
/// Can be executed with:
// forge script deploy/foundry/mintAgla.s.sol \
//     --sig "run(address[],uint256[],address)" \
//     "[0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B,0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA]" "[100000000000000000,100000000000000000]" "0x0000000000000000000000000000000000000000" \
//     --rpc-url $RPC_URL \
//     -vvvv
contract MintAglaScript is BaseScript {
    function run(address[] memory recipients, uint256[] memory amounts, address aglaToken) external broadcast {
        require(recipients.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            MockToken(aglaToken).mint(recipients[i], amounts[i]);

            // Log each mint operation
            console.log("Minted AGLA tokens:");
            console.log("Token address:", aglaToken);
            console.log("Recipient:", recipients[i]);
            console.log("Amount:", amounts[i]);
        }
    }
}
