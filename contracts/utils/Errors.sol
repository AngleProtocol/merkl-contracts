// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

error CampaignDoesNotExist();
error CampaignAlreadyExists();
error CampaignDurationBelowHour();
error CampaignRewardTokenNotWhitelisted();
error CampaignRewardTooLow();
error CampaignSouldStartInFuture();
error InvalidDispute();
error InvalidLengths();
error InvalidOverride();
error InvalidParam();
error InvalidParams();
error InvalidProof();
error InvalidUninitializedRoot();
error InvalidReturnMessage();
error InvalidReward();
error InvalidSignature();
error NoDispute();
error NoOverrideForCampaign();
error NotGovernor();
error NotGovernorOrGuardian();
error NotSigned();
error NotTrusted();
error NotUpgradeable();
error NotWhitelisted();
error ReentrantCall();
error UnresolvedDispute();
error ZeroAddress();
