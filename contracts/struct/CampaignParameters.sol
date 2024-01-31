// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

struct CampaignParameters {
    // Populated once created
    bytes32 campaignId;
    // Chosen by campaign creator
    address creator;
    address rewardToken;
    uint256 amount;
    uint32 campaignType;
    uint32 startTimestamp;
    uint32 duration; // in seconds, has to be a multiple of EPOCH
    bytes campaignData;
}
