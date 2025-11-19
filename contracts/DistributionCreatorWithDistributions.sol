// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { CampaignParameters } from "./struct/CampaignParameters.sol";
import { DistributionParameters } from "./struct/DistributionParameters.sol";
import { DistributionCreator } from "./DistributionCreator.sol";

/// @title DistributionCreatorWithDistributions
/// @author Merkl SAS
/// @notice Extended version of DistributionCreator that supports legacy distribution creation
/// @dev This contract maintains backward compatibility with the deprecated distribution model
/// @dev Two types of reward programs are distinguished:
/// - distributions: Legacy campaign format for concentrated liquidity pools (deprecated as of Feb 15, 2024)
/// - campaigns: Current universal format for all Merkl reward programs
/// @dev Primarily used on Polygon where some creators still utilize the legacy distribution model
//solhint-disable
contract DistributionCreatorWithDistributions is DistributionCreator {
    /// @notice Retrieves a legacy distribution and returns it as a campaign
    /// @param index Index of the distribution in the distributionList array
    /// @return Campaign parameters converted from the legacy distribution format
    function distribution(uint256 index) external view returns (CampaignParameters memory) {
        return _convertDistribution(distributionList[index]);
    }

    /// @notice Creates a legacy distribution to incentivize a liquidity pool over a specific time period
    /// @param newDistribution Distribution parameters in the legacy format
    /// @return distributionAmount Total amount of rewards allocated to the distribution
    /// @dev This function converts the legacy distribution to a campaign internally
    /// @dev Subject to the same signature requirements as campaign creation (hasSigned modifier)
    function createDistribution(
        DistributionParameters memory newDistribution
    ) external nonReentrant hasSigned returns (uint256 distributionAmount) {
        return _createDistribution(newDistribution);
    }

    /// @notice Internal function to create a distribution from legacy parameters
    /// @param newDistribution Legacy distribution parameters to convert and create
    /// @return Amount of rewards in the created campaign
    /// @dev Converts distribution to campaign format and calls _createCampaign
    /// @dev Not gas-efficient due to legacy support requirements
    function _createDistribution(DistributionParameters memory newDistribution) internal returns (uint256) {
        _createCampaign(_convertDistribution(newDistribution));
        // Not gas efficient but deprecated
        return campaignList[campaignList.length - 1].amount;
    }

    /// @notice Converts legacy distribution parameters into the current campaign format
    /// @param distributionToConvert Legacy distribution to be converted
    /// @return Equivalent campaign parameters in the current format
    /// @dev Extracts whitelist (wrapperType == 0) and blacklist (wrapperType == 3) from position wrappers
    /// @dev Uses assembly to resize arrays after filtering wrapper types
    /// @dev Campaign type is set to 2 for converted legacy distributions
    function _convertDistribution(
        DistributionParameters memory distributionToConvert
    ) internal view returns (CampaignParameters memory) {
        uint256 wrapperLength = distributionToConvert.wrapperTypes.length;
        address[] memory whitelist = new address[](wrapperLength);
        address[] memory blacklist = new address[](wrapperLength);
        uint256 whitelistLength;
        uint256 blacklistLength;
        // Filter position wrappers into whitelist and blacklist based on wrapper types
        for (uint256 k = 0; k < wrapperLength; k++) {
            if (distributionToConvert.wrapperTypes[k] == 0) {
                whitelist[whitelistLength] = (distributionToConvert.positionWrappers[k]);
                whitelistLength += 1;
            }
            if (distributionToConvert.wrapperTypes[k] == 3) {
                blacklist[blacklistLength] = (distributionToConvert.positionWrappers[k]);
                blacklistLength += 1;
            }
        }

        // Resize arrays to actual lengths using assembly
        assembly {
            mstore(whitelist, whitelistLength)
            mstore(blacklist, blacklistLength)
        }

        return
            CampaignParameters({
                campaignId: distributionToConvert.rewardId,
                creator: msg.sender,
                rewardToken: distributionToConvert.rewardToken,
                amount: distributionToConvert.amount,
                campaignType: 2,
                startTimestamp: distributionToConvert.epochStart,
                duration: distributionToConvert.numEpoch * HOUR,
                campaignData: abi.encode(
                    distributionToConvert.uniV3Pool,
                    distributionToConvert.propFees, // Proportion allocated to fee earners (e.g., 6000 = 60%)
                    distributionToConvert.propToken0, // Proportion for token0 holders (e.g., 3000 = 30%)
                    distributionToConvert.propToken1, // Proportion for token1 holders (e.g., 1000 = 10%)
                    distributionToConvert.isOutOfRangeIncentivized, // Whether out-of-range positions earn rewards (0 = no)
                    distributionToConvert.boostingAddress, // Address of boosting contract (NULL_ADDRESS if none)
                    distributionToConvert.boostedReward, // Additional reward multiplier for boosted positions (0 = no boost)
                    whitelist, // Addresses eligible to earn rewards (empty = all eligible)
                    blacklist, // Addresses excluded from earning rewards (empty = none excluded)
                    "0x" // Additional campaign-specific data (empty for legacy distributions)
                )
            });
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap2;
}
