// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

library Errors {
    error CampaignDoesNotExist();
    error CampaignAlreadyExists();
    error CampaignDurationBelowHour();
    error CampaignRewardTokenNotWhitelisted();
    error CampaignRewardTooLow();
    error CampaignShouldStartInFuture();
    error InvalidDispute();
    error InvalidLengths();
    error InvalidParam();
    error InvalidParams();
    error InvalidProof();
    error InvalidUninitializedRoot();
    error InvalidReward();
    error InvalidSignature();
    error NoDispute();
    error NotAllowed();
    error NotGovernor();
    error NotGovernorOrGuardian();
    error NotSigned();
    error NotTrusted();
    error NotWhitelisted();
    error UnresolvedDispute();
    error ZeroAddress();
    error DisputeFundsTransferFailed();
    error EthNotAccepted();
    error WithdrawalFailed();
    error InvalidClaim();
}
