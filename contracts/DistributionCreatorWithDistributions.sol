// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { UUPSHelper } from "./utils/UUPSHelper.sol";
import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";
import { Errors } from "./utils/Errors.sol";
import { CampaignParameters } from "./struct/CampaignParameters.sol";
import { DistributionParameters } from "./struct/DistributionParameters.sol";
import { RewardTokenAmounts } from "./struct/RewardTokenAmounts.sol";
import { Distributor } from "./Distributor.sol";
import { DistributionCreator } from "./DistributionCreator.sol";

/// @title DistributionCreatorWithDistributions
/// @author Merkl SAS
/// @notice Version of the DistributionCreator contract with the ability to create campaigns following the old
/// standard
/// @dev This contract distinguishes two types of different rewards:
/// - distributions: type of campaign for concentrated liquidity pools created before Feb 15 2024,
/// now deprecated
/// - campaigns: the more global name to describe any reward program on top of Merkl
/// @dev Useful notably on Polygon where some creators still use the old distribution model
//solhint-disable
contract DistributionCreatorWithDistributions is DistributionCreator {
    using SafeERC20 for IERC20;

    /// @notice Returns the distribution at a given index converted into a campaign
    function distribution(uint256 index) external view returns (CampaignParameters memory) {
        return _convertDistribution(distributionList[index]);
    }

    /// @notice Creates a `distribution` to incentivize a given pool for a specific period of time
    function createDistribution(
        DistributionParameters memory newDistribution
    ) external nonReentrant hasSigned returns (uint256 distributionAmount) {
        return _createDistribution(newDistribution);
    }

    /// @notice Creates a distribution from a deprecated distribution type
    function _createDistribution(DistributionParameters memory newDistribution) internal returns (uint256) {
        _createCampaign(_convertDistribution(newDistribution));
        // Not gas efficient but deprecated
        return campaignList[campaignList.length - 1].amount;
    }

    /// @notice Converts the deprecated distribution type into a campaign
    function _convertDistribution(
        DistributionParameters memory distributionToConvert
    ) internal view returns (CampaignParameters memory) {
        uint256 wrapperLength = distributionToConvert.wrapperTypes.length;
        address[] memory whitelist = new address[](wrapperLength);
        address[] memory blacklist = new address[](wrapperLength);
        uint256 whitelistLength;
        uint256 blacklistLength;
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
                    distributionToConvert.propFees, // eg. 6000
                    distributionToConvert.propToken0, // eg. 3000
                    distributionToConvert.propToken1, // eg. 1000
                    distributionToConvert.isOutOfRangeIncentivized, // eg. 0
                    distributionToConvert.boostingAddress, // eg. NULL_ADDRESS
                    distributionToConvert.boostedReward, // eg. 0
                    whitelist, // eg. []
                    blacklist, // eg. []
                    "0x"
                )
            });
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[31] private __gap;
}
