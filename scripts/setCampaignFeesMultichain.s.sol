// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";

contract SetCampaignFeesMultichain is BaseScript {
    function run() external broadcast {
        address creatorAddress = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        uint32 campaignType = 147;
        uint256 fees = 1;

        DistributionCreator(creatorAddress).setCampaignFees(campaignType, fees);
        console.log("setCampaignFees(%s, %s) executed on chain %s", campaignType, fees, block.chainid);
    }
}
