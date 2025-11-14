// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0;

/// @notice Parameters defining a Merkl reward distribution campaign
struct CampaignParameters {
    // ========== POPULATED BY CONTRACT ==========

    /// @notice Unique identifier for the campaign
    /// @dev Can be left as bytes32(0) when creating a new campaign - will be computed by the contract
    bytes32 campaignId;
    // ========== CONFIGURED BY CREATOR ==========

    /// @notice Address of the campaign creator
    /// @dev If set to address(0), will be automatically set to msg.sender when the campaign is created
    address creator;
    /// @notice Token distributed as rewards to campaign participants
    address rewardToken;
    /// @notice Total amount of rewardToken to distribute over the entire campaign duration
    /// @dev Must meet the minimum amount requirement for the reward token
    uint256 amount;
    /// @notice Type identifier for the campaign structure and rules
    /// @dev Different types may have different campaignData encoding schemes
    uint32 campaignType;
    /// @notice Unix timestamp when reward distribution begins
    uint32 startTimestamp;
    /// @notice Total duration of the campaign in seconds
    /// @dev Must be a multiple of EPOCH_DURATION (3600 seconds / 1 hour)
    /// @dev Must be at least EPOCH_DURATION (1 hour minimum)
    uint32 duration;
    /// @notice Encoded campaign-specific parameters
    /// @dev Encoding structure depends on campaignType
    /// @dev May include pool addresses, reward distribution rules, whitelists, etc.
    bytes campaignData;
}
