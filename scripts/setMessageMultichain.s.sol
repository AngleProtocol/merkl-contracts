// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";

contract SetMessageMultichain is BaseScript {
    function run() external broadcast {
        address creatorAddress = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        string memory newMessage = "I have read and accept the Merkl Terms & Conditions available at https://app.merkl.xyz/terms";

        DistributionCreator(creatorAddress).setMessage(newMessage);
        console.log("setMessage executed on chain %s", block.chainid);
        console.log("New message: %s", newMessage);
    }
}
