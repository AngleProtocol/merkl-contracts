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
    error InvalidOverride();
    error InvalidParam();
    error InvalidParams();
    error InvalidProof();
    error InvalidUninitializedRoot();
    error InvalidReallocation();
    error InvalidReturnMessage();
    error InvalidReward();
    error InvalidSignature();
    error KeyAlreadyUsed();
    error NoDispute();
    error NoOverrideForCampaign();
    error NotAllowed();
    error NotEnoughAllowance();
    error NotEnoughBalance();
    error NotEnoughPayment();
    error NotGovernor();
    error NotGovernorOrGuardian();
    error NotSigned();
    error NotTrusted();
    error NotUpgradeable();
    error NotWhitelisted();
    error OperatorNotAllowed();
    error UnresolvedDispute();
    error ZeroAddress();
    error DisputeFundsTransferFailed();
    error EthNotAccepted();
    error ReentrantCall();
    error WithdrawalFailed();
    error InvalidClaim();
    error RefererNotSet();
}
