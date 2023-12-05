// SPDX-License-Identifier: BUSL-1.1

/*
                  *                                                  █                              
                *****                                               ▓▓▓                             
                  *                                               ▓▓▓▓▓▓▓                         
                                   *            ///.           ▓▓▓▓▓▓▓▓▓▓▓▓▓                       
                                 *****        ////////            ▓▓▓▓▓▓▓                          
                                   *       /////////////            ▓▓▓                             
                     ▓▓                  //////////////////          █         ▓▓                   
                   ▓▓  ▓▓             ///////////////////////                ▓▓   ▓▓                
                ▓▓       ▓▓        ////////////////////////////           ▓▓        ▓▓              
              ▓▓            ▓▓    /////////▓▓▓///////▓▓▓/////////       ▓▓             ▓▓            
           ▓▓                 ,////////////////////////////////////// ▓▓                 ▓▓         
        ▓▓                  //////////////////////////////////////////                     ▓▓      
      ▓▓                  //////////////////////▓▓▓▓/////////////////////                          
                       ,////////////////////////////////////////////////////                        
                    .//////////////////////////////////////////////////////////                     
                     .//////////////////////////██.,//////////////////////////█                     
                       .//////////////////////████..,./////////////////////██                       
                        ...////////////////███████.....,.////////////////███                        
                          ,.,////////////████████ ........,///////////████                          
                            .,.,//////█████████      ,.......///////████                            
                               ,..//████████           ........./████                               
                                 ..,██████                .....,███                                 
                                    .██                     ,.,█                                    
                                                                                                    
                                                                                                    
                                                                                                    
               ▓▓            ▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓        ▓▓               ▓▓▓▓▓▓▓▓▓▓          
             ▓▓▓▓▓▓          ▓▓▓    ▓▓▓       ▓▓▓               ▓▓               ▓▓   ▓▓▓▓         
           ▓▓▓    ▓▓▓        ▓▓▓    ▓▓▓       ▓▓▓    ▓▓▓        ▓▓               ▓▓▓▓▓             
          ▓▓▓        ▓▓      ▓▓▓    ▓▓▓       ▓▓▓▓▓▓▓▓▓▓        ▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓          
*/

pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { IUniswapV3Pool } from "./interfaces/external/uniswap/IUniswapV3Pool.sol";

import "./utils/UUPSHelper.sol";
import { DistributionParameters } from "./struct/DistributionParameters.sol";
import { RewardTokenAmounts } from "./struct/RewardTokenAmounts.sol";

struct CampaignParameters {
    // Populated once created
    bytes32 campaignId;
    address creator;
    // Chosen by campaign creator
    address rewardToken;
    uint256 amount;
    uint32 campaignType;
    uint32 epochStart;
    uint32 numEpoch;
    bytes campaignData;
}

/// @title DistributionCreator
/// @author Angle Labs, Inc.
/// @notice Manages the distribution of rewards across different pools with concentrated liquidity (like on Uniswap V3)
/// @dev This contract is mostly a helper for APIs built on top of Merkl
/// @dev People depositing rewards must have signed a `message` with the conditions for using the
/// product
//solhint-disable
/**
TODO: differentiate guardian and governor roles
* */
contract DistributionCreator is UUPSHelper, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // =========================== CONSTANTS / VARIABLES ===========================

    /// @notice Epoch duration
    uint32 public constant EPOCH_DURATION = 3600;

    /// @notice Base for fee computation
    uint256 public constant BASE_9 = 1e9;

    /// @notice `Core` contract handling access control
    ICore public core;

    /// @notice User contract for distributing rewards
    address public distributor;

    /// @notice Address to which fees are forwarded
    address public feeRecipient;

    /// @notice Value (in base 10**9) of the fees taken when creating a distribution for a pool
    uint256 public fees;

    /// @notice Message that needs to be acknowledged by users creating a distribution
    string public message;

    /// @notice Hash of the message that needs to be signed
    bytes32 public messageHash;

    /// @notice List of all rewards ever distributed or to be distributed in the contract
    /// @dev An attacker could try to populate this list. It shouldn't be an issue as only view functions
    /// iterate on it
    DistributionParameters[] public distributionList;

    /// @notice Maps an address to its fee rebate
    mapping(address => uint256) public feeRebate;

    /// @notice Maps a token to whether it is whitelisted or not. No fees are to be paid for incentives given
    /// on pools with whitelisted tokens
    mapping(address => uint256) public isWhitelistedToken;

    /// @notice Maps an address to its nonce for creating a distribution
    mapping(address => uint256) public nonces;

    /// @notice Maps an address to the last valid hash signed
    mapping(address => bytes32) public userSignatures;

    /// @notice Maps a user to whether it is whitelisted for not signing
    mapping(address => uint256) public userSignatureWhitelist;

    /// @notice Maps a token to the minimum amount that must be sent per epoch for a distribution to be valid
    /// @dev If `rewardTokenMinAmounts[token] == 0`, then `token` cannot be used as a reward
    mapping(address => uint256) public rewardTokenMinAmounts;

    /// @notice List of all reward tokens that have at some point been accepted
    address[] public rewardTokens;

    uint256[36] private __gap;

    /// @notice List of all rewards ever distributed or to be distributed in the contract
    /// @dev An attacker could try to populate this list. It shouldn't be an issue as only view functions
    /// iterate on it
    CampaignParameters[] public campaignList;

    /// @notice Maps a campaignId to the ID of the campaign in the campaign list
    mapping(bytes32 => uint256) public campaignLookup;

    mapping(uint32 => uint256) public campaignSpecificFees;

    // =================================== EVENTS ==================================

    event DistributorUpdated(address indexed _distributor);
    event FeeRebateUpdated(address indexed user, uint256 userFeeRebate);
    event FeeRecipientUpdated(address indexed _feeRecipient);
    event FeesSet(uint256 _fees);
    event MessageUpdated(bytes32 _messageHash);
    event NewCampaign(CampaignParameters campaign);
    event NewDistribution(DistributionParameters distribution, address indexed sender);
    event RewardTokenMinimumAmountUpdated(address indexed token, uint256 amount);
    event TokenWhitelistToggled(address indexed token, uint256 toggleStatus);
    event UserSigned(bytes32 messageHash, address indexed user);
    event UserSigningWhitelistToggled(address indexed user, uint256 toggleStatus);

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!core.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!core.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether an address has signed the message or not
    modifier hasSigned() {
        if (
            userSignatureWhitelist[msg.sender] == 0 &&
            userSignatures[msg.sender] != messageHash &&
            userSignatureWhitelist[tx.origin] == 0 &&
            userSignatures[tx.origin] != messageHash
        ) revert NotSigned();
        _;
    }

    // ================================ CONSTRUCTOR ================================

    function initialize(ICore _core, address _distributor, uint256 _fees) external initializer {
        if (address(_core) == address(0) || _distributor == address(0)) revert ZeroAddress();
        if (_fees >= BASE_9) revert InvalidParam();
        distributor = _distributor;
        core = _core;
        fees = _fees;
    }

    constructor() initializer {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(core) {}

    // ============================== DEPOSIT FUNCTION =============================

    /// @notice Creates a `distribution` to incentivize a given pool for a specific period of time
    /// @return distributionAmount How many reward tokens are actually taken into consideration in the contract
    /// @dev If the address specified as a UniV3 pool is not effectively a pool, it will not be handled by the
    /// distribution script and rewards may be lost
    /// @dev Reward tokens sent as part of distributions must have been whitelisted before and amounts
    /// sent should be bigger than a minimum amount specific to each token
    /// @dev The `positionWrappers` specified in the `distribution` struct need to be supported by the script
    /// List of supported `positionWrappers` can be found in the docs.
    /// @dev If the pool incentivized contains one whitelisted token, then no fees are taken on the rewards
    /// @dev This function reverts if the sender has not signed the message `messageHash` once through one of
    /// the functions enabling to sign
    function createDistribution(
        DistributionParameters memory distribution
    ) external hasSigned returns (uint256 distributionAmount) {
        return _createDistribution(distribution);
    }

    /// @notice Same as the function above but for multiple distributions at once
    /// @return List of all the distribution amounts actually deposited for each `distribution` in the `distributions` list
    function createDistributions(
        DistributionParameters[] memory distributions
    ) external hasSigned returns (uint256[] memory) {
        uint256 distributionsLength = distributions.length;
        uint256[] memory distributionAmounts = new uint256[](distributionsLength);
        for (uint256 i; i < distributionsLength; ) {
            distributionAmounts[i] = _createDistribution(distributions[i]);
            unchecked {
                ++i;
            }
        }
        return distributionAmounts;
    }

    /// @notice Creates a `campaign` to incentivize a given pool for a specific period of time
    /// @return campaignAmount How many reward tokens are actually taken into consideration in the contract
    /// @dev If the campaign is badly specified, it will not be handled by the campaign script and rewards may be lost
    /// @dev Reward tokens sent as part of campaigns must have been whitelisted before and amounts
    /// sent should be bigger than a minimum amount specific to each token
    /// @dev This function reverts if the sender has not signed the message `messageHash` once through one of
    /// the functions enabling to sign
    function createCampaign(CampaignParameters memory campaign) external hasSigned returns (uint256 campaignAmount) {
        return _createCampaign(campaign);
    }

    /// @notice Same as the function above but for multiple campaigns at once
    /// @return List of all the campaign amounts actually deposited for each `campaign` in the `campaigns` list
    function createCampaigns(CampaignParameters[] memory campaigns) external hasSigned returns (uint256[] memory) {
        uint256 campaignsLength = campaigns.length;
        uint256[] memory campaignAmounts = new uint256[](campaignsLength);
        for (uint256 i; i < campaignsLength; ) {
            campaignAmounts[i] = _createCampaign(campaigns[i]);
            unchecked {
                ++i;
            }
        }
        return campaignAmounts;
    }

    /// @notice Checks whether the `msg.sender`'s `signature` is compatible with the message
    /// to sign and stores the signature
    /// @dev If you signed the message once, and the message has not been modified, then you do not
    /// need to sign again
    function sign(bytes calldata signature) external {
        _sign(signature);
    }

    function acceptConditions() external {
        userSignatureWhitelist[msg.sender] = 1;
    }

    /// @notice Combines signing the message and creating a distribution
    function signAndCreateDistribution(
        DistributionParameters memory distribution,
        bytes calldata signature
    ) external returns (uint256 distributionAmount) {
        _sign(signature);
        return _createDistribution(distribution);
    }

    /// @notice Combines signing the message and creating a campaign
    function signAndCreateCampaign(
        CampaignParameters memory campaign,
        bytes calldata signature
    ) external returns (uint256 campaignAmount) {
        _sign(signature);
        return _createCampaign(campaign);
    }

    /// @notice Internal version of `createCampaign`
    function _createCampaign(
        CampaignParameters memory campaign
    ) internal nonReentrant returns (uint256 campaignAmountMinusFees) {
        uint32 epochStart = _getRoundedEpoch(campaign.epochStart);
        campaign.epochStart = epochStart;
        _invalidateCampaign(
            epochStart,
            campaign.amount,
            campaign.numEpoch,
            rewardTokenMinAmounts[campaign.rewardToken]
        );
        // Computing fees: these are waived for whitelisted addresses and if there is a whitelisted token in a pool
        uint256 _fees = campaignSpecificFees[campaign.campaignType];
        if (_fees == 0) _fees = fees;
        bytes32 campaignId;
        (campaignAmountMinusFees, campaignId) = _computeFees(_fees, campaign.amount, campaign.rewardToken);
        campaign.amount = campaignAmountMinusFees;
        campaign.campaignId = campaignId;
        campaign.creator = msg.sender;
        uint256 lookupIndex = campaignList.length;
        campaignLookup[campaignId] = lookupIndex;
        campaignList.push(campaign);
        emit NewCampaign(campaign);
    }

    function _invalidateCampaign(
        uint256 epochStart,
        uint256 amount,
        uint256 numEpoch,
        uint256 minCampaignAmount
    ) internal view {
        if (
            // if epoch parameters lead to a past campaign
            epochStart + EPOCH_DURATION < block.timestamp ||
            // if the amount of epochs for which this campaign should last is zero
            numEpoch == 0 ||
            // if the reward token is not whitelisted as an incentive token
            minCampaignAmount == 0 ||
            // if the amount distributed is too small with respect to what is allowed
            amount / numEpoch < minCampaignAmount
        ) revert InvalidReward();
    }

    /// @notice Internal version of `createDistribution`
    function _createDistribution(
        DistributionParameters memory distribution
    ) internal nonReentrant returns (uint256 distributionAmountMinusFees) {
        uint32 epochStart = _getRoundedEpoch(distribution.epochStart);
        distribution.epochStart = epochStart;
        _invalidateCampaign(
            epochStart,
            distribution.amount,
            distribution.numEpoch,
            rewardTokenMinAmounts[distribution.rewardToken]
        );
        if (
            // if the distribution parameters are not correctly specified
            distribution.propFees + distribution.propToken0 + distribution.propToken1 != 1e4 ||
            // if boosted addresses get less than non-boosted addresses in case of
            (distribution.boostingAddress != address(0) && distribution.boostedReward < 1e4) ||
            // if the type of the position wrappers is not well specified
            distribution.positionWrappers.length != distribution.wrapperTypes.length
        ) revert InvalidReward();
        // Computing fees: these are waived for whitelisted addresses and if there is a whitelisted token in a pool
        uint256 _fees;
        if (
            isWhitelistedToken[IUniswapV3Pool(distribution.uniV3Pool).token0()] == 0 &&
            isWhitelistedToken[IUniswapV3Pool(distribution.uniV3Pool).token1()] == 0
        ) _fees = fees;
        bytes32 campaignId;
        (distributionAmountMinusFees, campaignId) = _computeFees(_fees, distribution.amount, distribution.rewardToken);
        distribution.amount = distributionAmountMinusFees;
        distribution.rewardId = campaignId;
        distributionList.push(distribution);
        emit NewDistribution(distribution, msg.sender);
    }

    function _computeFees(
        uint256 baseFeesValue,
        uint256 distributionAmount,
        address rewardToken
    ) internal returns (uint256 distributionAmountMinusFees, bytes32 campaignId) {
        uint256 _fees = (baseFeesValue * (BASE_9 - feeRebate[msg.sender])) / BASE_9;
        distributionAmountMinusFees = distributionAmount;
        if (_fees != 0) {
            distributionAmountMinusFees = (distributionAmount * (BASE_9 - _fees)) / BASE_9;
            address _feeRecipient = feeRecipient;
            _feeRecipient = _feeRecipient == address(0) ? address(this) : _feeRecipient;
            IERC20(rewardToken).safeTransferFrom(
                msg.sender,
                _feeRecipient,
                distributionAmount - distributionAmountMinusFees
            );
        }
        IERC20(rewardToken).safeTransferFrom(msg.sender, distributor, distributionAmountMinusFees);
        uint256 senderNonce = nonces[msg.sender];
        nonces[msg.sender] = senderNonce + 1;
        campaignId = bytes32(keccak256(abi.encodePacked(msg.sender, senderNonce)));
    }

    /// @notice Internal version of the `sign` function
    function _sign(bytes calldata signature) internal {
        bytes32 _messageHash = messageHash;
        if (ECDSA.recover(_messageHash, signature) != msg.sender) revert InvalidSignature();
        userSignatures[msg.sender] = _messageHash;
        emit UserSigned(_messageHash, msg.sender);
    }

    // ================================= UI HELPERS ================================
    // These functions are not to be queried on-chain and hence are not optimized for gas consumption

    /// @notice Returns the list of all the reward tokens supported as well as their minimum amounts
    function getValidRewardTokens() external view returns (RewardTokenAmounts[] memory) {
        uint256 length;
        uint256 rewardTokenListLength = rewardTokens.length;
        RewardTokenAmounts[] memory validRewardTokens = new RewardTokenAmounts[](rewardTokenListLength);
        for (uint32 i; i < rewardTokenListLength; ) {
            address token = rewardTokens[i];
            uint256 minAmount = rewardTokenMinAmounts[token];
            if (minAmount > 0) {
                validRewardTokens[length] = RewardTokenAmounts(token, minAmount);
                length += 1;
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(validRewardTokens, length)
        }
        return validRewardTokens;
    }

    /// @notice Returns the list of all campaigns ever made or to be done in the future
    function getAllCampaigns() external view returns (CampaignParameters[] memory) {
        return campaignList;
    }

    /// @notice Similar to `getCampaignsBetweenEpochs(uint256 epochStart, uint256 epochEnd)` with additional parameters to prevent out of gas error
    /// @param skip Disregard distibutions with a global index lower than `skip`
    /// @param first Limit the length of the returned array to `first`
    /// @return searchCampaigns Eligible campaigns
    /// @return lastIndexCampaign Index of the last campaign assessed in the list of all campaigns
    /// For pagniation purpose, in case of out of gas, you can call back the same function but with `skip` set to `lastIndexCampaign`
    function getCampaignsBetweenEpochs(
        uint32 epochStart,
        uint32 epochEnd,
        uint32 skip,
        uint32 first
    ) external view returns (CampaignParameters[] memory, uint256 lastIndexCampaign) {
        return _getCampaignsBetweenEpochs(_getRoundedEpoch(epochStart), _getRoundedEpoch(epochEnd), skip, first);
    }

    /// @notice Returns the list of all distributions ever made or to be done in the future
    function getAllDistributions() external view returns (DistributionParameters[] memory) {
        return distributionList;
    }

    /// @notice Similar to `getDistributionsBetweenEpochs(uint256 epochStart, uint256 epochEnd)` with additional parameters to prevent out of gas error
    /// @param skip Disregard distibutions with a global index lower than `skip`
    /// @param first Limit the length of the returned array to `first`
    /// @return searchDistributions Eligible distributions
    /// @return lastIndexDistribution Index of the last distribution assessed in the list of all distributions
    /// For pagniation purpose, in case of out of gas, you can call back the same function but with `skip` set to `lastIndexDistribution`
    function getDistributionsBetweenEpochs(
        uint32 epochStart,
        uint32 epochEnd,
        uint32 skip,
        uint32 first
    ) external view returns (DistributionParameters[] memory, uint256 lastIndexDistribution) {
        return _getDistributionsBetweenEpochs(_getRoundedEpoch(epochStart), _getRoundedEpoch(epochEnd), skip, first);
    }

    // ============================ GOVERNANCE FUNCTIONS ===========================

    /// @notice Sets a new `distributor` to which rewards should be distributed
    function setNewDistributor(address _distributor) external onlyGovernor {
        if (_distributor == address(0)) revert InvalidParam();
        distributor = _distributor;
        emit DistributorUpdated(_distributor);
    }

    /// @notice Sets the fees on deposit
    function setFees(uint256 _fees) external onlyGovernor {
        if (_fees >= BASE_9) revert InvalidParam();
        fees = _fees;
        emit FeesSet(_fees);
    }

    function setCampaignFees(uint32 campaignType, uint256 _fees) external onlyGovernor {
        campaignSpecificFees[campaignType] = _fees;
    }

    /// @notice Toggles the fee whitelist for `token`
    function toggleTokenWhitelist(address token) external onlyGovernor {
        uint256 toggleStatus = 1 - isWhitelistedToken[token];
        isWhitelistedToken[token] = toggleStatus;
        emit TokenWhitelistToggled(token, toggleStatus);
    }

    /// @notice Recovers fees accrued on the contract for a list of `tokens`
    function recoverFees(IERC20[] calldata tokens, address to) external onlyGovernor {
        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength; ) {
            tokens[i].safeTransfer(to, tokens[i].balanceOf(address(this)));
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets fee rebates for a given user
    function setUserFeeRebate(address user, uint256 userFeeRebate) external onlyGovernorOrGuardian {
        feeRebate[user] = userFeeRebate;
        emit FeeRebateUpdated(user, userFeeRebate);
    }

    /// @notice Sets the minimum amounts per distribution epoch for different reward tokens
    function setRewardTokenMinAmounts(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external onlyGovernorOrGuardian {
        uint256 tokensLength = tokens.length;
        if (tokensLength != amounts.length) revert InvalidLengths();
        for (uint256 i; i < tokensLength; ++i) {
            uint256 amount = amounts[i];
            // Basic logic check to make sure there are no duplicates in the `rewardTokens` table. If a token is
            // removed then re-added, it will appear as a duplicate in the list
            if (amount > 0 && rewardTokenMinAmounts[tokens[i]] == 0) rewardTokens.push(tokens[i]);
            rewardTokenMinAmounts[tokens[i]] = amount;
            emit RewardTokenMinimumAmountUpdated(tokens[i], amount);
        }
    }

    /// @notice Sets a new address to receive fees
    function setFeeRecipient(address _feeRecipient) external onlyGovernor {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /// @notice Sets the message that needs to be signed by users before posting rewards
    function setMessage(string memory _message) external onlyGovernor {
        message = _message;
        bytes32 _messageHash = ECDSA.toEthSignedMessageHash(bytes(_message));
        messageHash = _messageHash;
        emit MessageUpdated(_messageHash);
    }

    /// @notice Toggles the whitelist status for `user` when it comes to signing messages before depositing rewards.
    function toggleSigningWhitelist(address user) external onlyGovernorOrGuardian {
        uint256 whitelistStatus = 1 - userSignatureWhitelist[user];
        userSignatureWhitelist[user] = whitelistStatus;
        emit UserSigningWhitelistToggled(user, whitelistStatus);
    }

    // ============================== INTERNAL HELPERS =============================

    /// @notice Rounds an `epoch` timestamp to the start of the corresponding period
    function _getRoundedEpoch(uint32 epoch) internal pure returns (uint32) {
        return (epoch / EPOCH_DURATION) * EPOCH_DURATION;
    }

    /// @notice Checks whether `campaign` was live between `roundedEpochStart` and `roundedEpochEnd`
    function _isCampaignLiveBetweenEpochs(
        CampaignParameters memory campaign,
        uint32 roundedEpochStart,
        uint32 roundedEpochEnd
    ) internal pure returns (bool) {
        uint256 campaignEpochStart = campaign.epochStart;
        return (campaignEpochStart + campaign.numEpoch * EPOCH_DURATION > roundedEpochStart &&
            campaignEpochStart < roundedEpochEnd);
    }

    /// @notice Gets the list of all the campaigns for `uniV3Pool` that have been active between `epochStart` and `epochEnd` (excluded)
    /// @dev If the `uniV3Pool` parameter is equal to 0, then this function will return the campaigns for all pools
    function _getCampaignsBetweenEpochs(
        uint32 epochStart,
        uint32 epochEnd,
        uint32 skip,
        uint32 first
    ) internal view returns (CampaignParameters[] memory, uint256) {
        uint256 length;
        uint256 campaignListLength = campaignList.length;
        uint256 returnSize = first > campaignListLength ? campaignListLength : first;
        CampaignParameters[] memory activeRewards = new CampaignParameters[](returnSize);
        uint32 i = skip;
        while (i < campaignListLength) {
            CampaignParameters memory campaign = campaignList[i];
            if (_isCampaignLiveBetweenEpochs(campaign, epochStart, epochEnd)) {
                activeRewards[length] = campaign;
                length += 1;
            }
            unchecked {
                ++i;
            }
            if (length == returnSize) break;
        }
        assembly {
            mstore(activeRewards, length)
        }
        return (activeRewards, i);
    }

    /// @notice Checks whether `distribution` was live between `roundedEpochStart` and `roundedEpochEnd`
    function _isDistributionLiveBetweenEpochs(
        DistributionParameters memory distribution,
        uint32 roundedEpochStart,
        uint32 roundedEpochEnd
    ) internal pure returns (bool) {
        uint256 distributionEpochStart = distribution.epochStart;
        return (distributionEpochStart + distribution.numEpoch * EPOCH_DURATION > roundedEpochStart &&
            distributionEpochStart < roundedEpochEnd);
    }

    /// @notice Gets the list of all the distributions for `uniV3Pool` that have been active between `epochStart` and `epochEnd` (excluded)
    /// @dev If the `uniV3Pool` parameter is equal to 0, then this function will return the distributions for all pools
    function _getDistributionsBetweenEpochs(
        uint32 epochStart,
        uint32 epochEnd,
        uint32 skip,
        uint32 first
    ) internal view returns (DistributionParameters[] memory, uint256) {
        uint256 length;
        uint256 distributionListLength = distributionList.length;
        uint256 returnSize = first > distributionListLength ? distributionListLength : first;
        DistributionParameters[] memory activeRewards = new DistributionParameters[](returnSize);
        uint32 i = skip;
        while (i < distributionListLength) {
            DistributionParameters memory distribution = distributionList[i];
            if (_isDistributionLiveBetweenEpochs(distribution, epochStart, epochEnd)) {
                activeRewards[length] = distribution;
                length += 1;
            }
            unchecked {
                ++i;
            }
            if (length == returnSize) break;
        }
        assembly {
            mstore(activeRewards, length)
        }
        return (activeRewards, i);
    }
}
