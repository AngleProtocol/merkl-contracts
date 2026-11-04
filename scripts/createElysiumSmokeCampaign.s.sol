// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { console } from "forge-std/console.sol";
import { BaseScript } from "./utils/Base.s.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { CampaignParameters } from "../contracts/struct/CampaignParameters.sol";

/// @notice Prepare a one-hour USDC-balance campaign paying 10,000 aglaMerkl before protocol fees.
/// @dev Forge simulates by default. Broadcasting requires the explicit --broadcast flag.
contract CreateElysiumSmokeCampaign is BaseScript {
    address public constant CREATOR = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
    address public constant REWARD = 0x999BAcD74539e19e3371E51839707b59A682B258;
    address public constant TARGET = 0xb47c4C8F73F009CC0C0d3f92B388d13E293F0B65;
    address public constant OPERATOR = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
    uint32 public constant CAMPAIGN_TYPE = 18; // ERC20LOGPROCESSOR
    uint32 public constant DURATION = 3600;

    DistributionCreator internal constant creator = DistributionCreator(CREATOR);
    IERC20Metadata internal constant token = IERC20Metadata(REWARD);

    function run(uint32 startTimestamp) external returns (bytes32 campaignId) {
        require(block.chainid == 99901, "Expected Elysium mainnet");
        require(broadcaster == OPERATOR, "Expected regular deployer");
        require(uint256(startTimestamp) >= block.timestamp + 300, "Start needs five minutes lead time");
        require(CREATOR.code.length != 0 && TARGET.code.length != 0, "Missing contract code");

        uint256 amount = 10_000 * 10 ** uint256(token.decimals());
        uint256 minAmount = creator.rewardTokenMinAmounts(REWARD);
        require(minAmount != 0, "Reward token not allowed");
        // Same rule as DistributionCreator._createCampaign, checked before fees.
        require(amount * creator.HOUR() >= minAmount * DURATION, "Reward below token minimum");
        // Tokens come from the predeposited balance when it covers the amount, otherwise from the wallet.
        bool usePredeposit = creator.creatorBalance(broadcaster, REWARD) >= amount;
        require(usePredeposit || token.balanceOf(broadcaster) >= amount, "Insufficient aglaMerkl balance");

        // Canonical erc20LogProcessor decoding: time-weighted balances, default scoring and distribution, no hooks.
        bytes memory data = abi.encode(TARGET, new address[](0), new address[](0), "", bytes(""), bytes(""), new bytes[](0));
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: bytes32(0),
            creator: broadcaster,
            rewardToken: REWARD,
            amount: amount,
            campaignType: CAMPAIGN_TYPE,
            startTimestamp: startTimestamp,
            duration: DURATION,
            campaignData: data
        });

        campaignId = _create(campaign, usePredeposit);

        CampaignParameters memory stored = creator.campaign(campaignId);
        require(stored.creator == broadcaster && stored.rewardToken == REWARD, "Unexpected campaign");
        require(stored.amount > 0 && stored.amount <= amount, "Unexpected net rewards");
        require(stored.startTimestamp == startTimestamp && stored.duration == DURATION, "Unexpected campaign timing");
        require(stored.campaignType == CAMPAIGN_TYPE && keccak256(stored.campaignData) == keccak256(data), "Unexpected campaign strategy");
        console.log("Campaign ID:", vm.toString(campaignId));
        console.log("Start:", uint256(startTimestamp));
        console.log("End:", uint256(startTimestamp) + DURATION);
        console.log("Gross rewards (base units):", amount);
        console.log("Net rewards (base units):", stored.amount);
    }

    function _create(CampaignParameters memory campaign, bool usePredeposit) internal broadcast returns (bytes32) {
        bool signed = creator.userSignatureWhitelist(broadcaster) != 0 || creator.userSignatures(broadcaster) == creator.messageHash();
        if (!signed) creator.acceptConditions();
        if (!usePredeposit) require(token.approve(CREATOR, campaign.amount), "Approval failed");
        return creator.createCampaign(campaign);
    }
}
