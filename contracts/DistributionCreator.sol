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
import { CampaignParameters } from "./struct/CampaignParameters.sol";
import { DistributionParameters } from "./struct/DistributionParameters.sol";
import { RewardTokenAmounts } from "./struct/RewardTokenAmounts.sol";

/// @title DistributionCreator
/// @author Angle Labs, Inc.
/// @notice Manages the distribution of rewards through the Merkl system
/// @dev This contract is mostly a helper for APIs built on top of Merkl
/// @dev This contract is an upgraded version and distinguishes two types of different rewards:
/// - distributions: type of campaign for concentrated liquidity pools created before Feb 15 2024,
/// now deprecated
/// - campaigns: the new more global name to describe any reward program on top of Merkl
//solhint-disable
contract DistributionCreator is UUPSHelper, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 CONSTANTS / VARIABLES                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    uint32 public constant HOUR = 3600;

    /// @notice Base for fee computation
    uint256 public constant BASE_9 = 1e9;

    uint256 public immutable CHAIN_ID = block.chainid;

    /// @notice `Core` contract handling access control
    ICore public core;

    /// @notice Contract distributing rewards to users
    address public distributor;

    /// @notice Address to which fees are forwarded
    address public feeRecipient;

    /// @notice Value (in base 10**9) of the fees taken when creating a campaign
    uint256 public defaultFees;

    /// @notice Message that needs to be acknowledged by users creating a campaign
    string public message;

    /// @notice Hash of the message that needs to be signed
    bytes32 public messageHash;

    /// @notice List of all rewards distributed in the contract on campaigns created before mid Feb 2024
    /// for concentrated liquidity pools
    DistributionParameters[] public distributionList;

    /// @notice Maps an address to its fee rebate
    mapping(address => uint256) public feeRebate;

    /// @notice Maps a token to whether it is whitelisted or not. No fees are to be paid for incentives given
    /// on pools with whitelisted tokens
    mapping(address => uint256) public isWhitelistedToken;

    /// @notice Deprecated, kept for storage compatibility
    mapping(address => uint256) public _nonces;

    /// @notice Maps an address to the last valid hash signed
    mapping(address => bytes32) public userSignatures;

    /// @notice Maps a user to whether it is whitelisted for not signing
    mapping(address => uint256) public userSignatureWhitelist;

    /// @notice Maps a token to the minimum amount that must be sent per epoch for a distribution to be valid
    /// @dev If `rewardTokenMinAmounts[token] == 0`, then `token` cannot be used as a reward
    mapping(address => uint256) public rewardTokenMinAmounts;

    /// @notice List of all reward tokens that have at some point been accepted
    address[] public rewardTokens;

    /// @notice List of all rewards ever distributed or to be distributed in the contract
    /// @dev An attacker could try to populate this list. It shouldn't be an issue as only view functions
    /// iterate on it
    CampaignParameters[] public campaignList;

    /// @notice Maps a campaignId to the ID of the campaign in the campaign list + 1
    mapping(bytes32 => uint256) internal _campaignLookup;

    /// @notice Maps a campaign type to the fees for this specific campaign
    mapping(uint32 => uint256) public campaignSpecificFees;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    event DistributorUpdated(address indexed _distributor);
    event FeeRebateUpdated(address indexed user, uint256 userFeeRebate);
    event FeeRecipientUpdated(address indexed _feeRecipient);
    event FeesSet(uint256 _fees);
    event CampaignSpecificFeesSet(uint32 campaignType, uint256 _fees);
    event MessageUpdated(bytes32 _messageHash);
    event NewCampaign(CampaignParameters campaign);
    event NewDistribution(DistributionParameters distribution, address indexed sender);
    event RewardTokenMinimumAmountUpdated(address indexed token, uint256 amount);
    event TokenWhitelistToggled(address indexed token, uint256 toggleStatus);
    event UserSigned(bytes32 messageHash, address indexed user);
    event UserSigningWhitelistToggled(address indexed user, uint256 toggleStatus);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function initialize(ICore _core, address _distributor, uint256 _fees) external initializer {
        if (address(_core) == address(0) || _distributor == address(0)) revert ZeroAddress();
        if (_fees >= BASE_9) revert InvalidParam();
        distributor = _distributor;
        core = _core;
        defaultFees = _fees;
    }

    constructor() initializer {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(core) {}

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 USER FACING FUNCTIONS                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a `campaign` to incentivize a given pool for a specific period of time
    /// @return The campaignId of the new campaign
    /// @dev If the campaign is badly specified, it will not be handled by the campaign script and rewards may be lost
    /// @dev Reward tokens sent as part of campaigns must have been whitelisted before and amounts
    /// sent should be bigger than a minimum amount specific to each token
    /// @dev This function reverts if the sender has not accepted the terms and conditions
    function createCampaign(CampaignParameters memory newCampaign) external nonReentrant hasSigned returns (bytes32) {
        return _createCampaign(newCampaign);
    }

    /// @notice Same as the function above but for multiple campaigns at once
    /// @return List of all the campaign amounts actually deposited for each `campaign` in the `campaigns` list
    function createCampaigns(
        CampaignParameters[] memory campaigns
    ) external nonReentrant hasSigned returns (bytes32[] memory) {
        uint256 campaignsLength = campaigns.length;
        bytes32[] memory campaignIds = new bytes32[](campaignsLength);
        for (uint256 i; i < campaignsLength; ) {
            campaignIds[i] = _createCampaign(campaigns[i]);
            unchecked {
                ++i;
            }
        }
        return campaignIds;
    }

    /// @notice Allows a user to accept the conditions without signing the message
    /// @dev Users may either call `acceptConditions` here or `sign` the message
    function acceptConditions() external {
        userSignatureWhitelist[msg.sender] = 1;
    }

    /// @notice Checks whether the `msg.sender`'s `signature` is compatible with the message
    /// to sign and stores the signature
    /// @dev If you signed the message once, and the message has not been modified, then you do not
    /// need to sign again
    function sign(bytes calldata signature) external {
        _sign(signature);
    }

    /// @notice Combines signing the message and creating a campaign
    function signAndCreateCampaign(
        CampaignParameters memory newCampaign,
        bytes calldata signature
    ) external returns (bytes32) {
        _sign(signature);
        return _createCampaign(newCampaign);
    }

    /// @notice Creates a `distribution` to incentivize a given pool for a specific period of time
    function createDistribution(
        DistributionParameters memory newDistribution
    ) external nonReentrant hasSigned returns (uint256 distributionAmount) {
        return _createDistribution(newDistribution);
    }

    /// @notice Same as the function above but for multiple distributions at once
    function createDistributions(
        DistributionParameters[] memory distributions
    ) external nonReentrant hasSigned returns (uint256[] memory) {
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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the distribution at a given index converted into a campaign
    function distribution(uint256 index) external view returns (CampaignParameters memory) {
        return _convertDistribution(distributionList[index]);
    }

    /// @notice Returns the index of a campaign in the campaign list
    function campaignLookup(bytes32 _campaignId) public view returns (uint256) {
        uint256 index = _campaignLookup[_campaignId];
        if (index == 0) revert CampaignDoesNotExist();
        return index - 1;
    }

    /// @notice Returns the campaign parameters of a given campaignId
    function campaign(bytes32 _campaignId) external view returns (CampaignParameters memory) {
        return campaignList[campaignLookup(_campaignId)];
    }

    /// @notice Returns the campaign ID for a given campaign
    /// @dev The campaign ID is computed as the hash of the following parameters:
    ///  - `campaign.creator`
    ///  - `campaign.rewardToken`
    ///  - `campaign.campaignType`
    ///  - `campaign.startTimestamp`
    ///  - `campaign.duration`
    ///  - `campaign.campaignData`
    /// This prevents the creation by the same account of two campaigns with the same parameters
    /// which is not a huge issue
    function campaignId(CampaignParameters memory campaignData) public view returns (bytes32) {
        return
            bytes32(
                keccak256(
                    abi.encodePacked(
                        CHAIN_ID,
                        campaignData.creator,
                        campaignData.rewardToken,
                        campaignData.campaignType,
                        campaignData.startTimestamp,
                        campaignData.duration,
                        campaignData.campaignData
                    )
                )
            );
    }

    /// @notice Returns the list of all the reward tokens supported as well as their minimum amounts
    /// @dev Not to be queried on-chain and hence not optimized for gas consumption
    function getValidRewardTokens() external view returns (RewardTokenAmounts[] memory) {
        (RewardTokenAmounts[] memory validRewardTokens, ) = _getValidRewardTokens(0, type(uint32).max);
        return validRewardTokens;
    }

    /// @dev Not to be queried on-chain and hence not optimized for gas consumption
    function getValidRewardTokens(
        uint32 skip,
        uint32 first
    ) external view returns (RewardTokenAmounts[] memory, uint256) {
        return _getValidRewardTokens(skip, first);
    }

    /// @notice Gets all the campaigns which were live at some point between `start` and `end` timestamp
    /// @param skip Disregard distibutions with a global index lower than `skip`
    /// @param first Limit the length of the returned array to `first`
    /// @return searchCampaigns Eligible campaigns
    /// @return lastIndexCampaign Index of the last campaign assessed in the list of all campaigns
    /// @dev For pagniation purpose, in case of out of gas, you can call back the same function but with `skip` set to `lastIndexCampaign`
    /// @dev Not to be queried on-chain and hence not optimized for gas consumption
    function getCampaignsBetween(
        uint32 start,
        uint32 end,
        uint32 skip,
        uint32 first
    ) external view returns (CampaignParameters[] memory, uint256 lastIndexCampaign) {
        return _getCampaignsBetween(start, end, skip, first);
    }

    /// @notice Gets all the distributions which were live at some point between `start` and `end` timestamp
    /// @param skip Disregard distibutions with a global index lower than `skip`
    /// @param first Limit the length of the returned array to `first`
    /// @return searchDistributions Eligible distributions
    /// @return lastIndexDistribution Index of the last distribution assessed in the list of all distributions
    /// @dev For pagniation purpose, in case of out of gas, you can call back the same function but with `skip` set to `lastIndexDistribution`
    /// @dev Not to be queried on-chain and hence not optimized for gas consumption
    function getDistributionsBetweenEpochs(
        uint32 epochStart,
        uint32 epochEnd,
        uint32 skip,
        uint32 first
    ) external view returns (DistributionParameters[] memory, uint256 lastIndexDistribution) {
        return _getDistributionsBetweenEpochs(_getRoundedEpoch(epochStart), _getRoundedEpoch(epochEnd), skip, first);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GOVERNANCE FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets a new `distributor` to which rewards should be distributed
    function setNewDistributor(address _distributor) external onlyGovernor {
        if (_distributor == address(0)) revert InvalidParam();
        distributor = _distributor;
        emit DistributorUpdated(_distributor);
    }

    /// @notice Sets the defaultFees on deposit
    function setFees(uint256 _defaultFees) external onlyGovernor {
        if (_defaultFees >= BASE_9) revert InvalidParam();
        defaultFees = _defaultFees;
        emit FeesSet(_defaultFees);
    }

    function setCampaignFees(uint32 campaignType, uint256 _fees) external onlyGovernor {
        if (_fees >= BASE_9) revert InvalidParam();
        campaignSpecificFees[campaignType] = _fees;
        emit CampaignSpecificFeesSet(campaignType, _fees);
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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNAL                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal version of `createCampaign`
    function _createCampaign(CampaignParameters memory newCampaign) internal returns (bytes32) {
        uint256 rewardTokenMinAmount = rewardTokenMinAmounts[newCampaign.rewardToken];
        // if epoch parameters lead to a past campaign
        if (newCampaign.startTimestamp < block.timestamp) revert CampaignSouldStartInFuture();
        // if the campaign doesn't last at least one second
        if (newCampaign.duration == 0) revert CampaignDurationIsZero();
        // if the reward token is not whitelisted as an incentive token
        if (rewardTokenMinAmount == 0) revert CampaignRewardTokenNotWhitelisted();
        // if the amount distributed is too small with respect to what is allowed
        if ((newCampaign.amount * HOUR) / newCampaign.duration < rewardTokenMinAmount) revert CampaignRewardTooLow();

        if (newCampaign.creator == address(0)) newCampaign.creator = msg.sender;

        // Computing fees: these are waived for whitelisted addresses and if there is a whitelisted token in a pool
        uint256 _fees = campaignSpecificFees[newCampaign.campaignType];
        if (_fees == 1) _fees = 0;
        else if (_fees == 0) _fees = defaultFees;
        uint256 campaignAmountMinusFees = _computeFees(_fees, newCampaign.amount, newCampaign.rewardToken);
        newCampaign.amount = campaignAmountMinusFees;

        newCampaign.campaignId = campaignId(newCampaign);

        if (_campaignLookup[newCampaign.campaignId] != 0) revert CampaignAlreadyExists();
        _campaignLookup[newCampaign.campaignId] = campaignList.length + 1;
        campaignList.push(newCampaign);
        emit NewCampaign(newCampaign);

        return newCampaign.campaignId;
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

    /// @notice Computes the fees to be taken on a campaign and transfers them to the fee recipient
    function _computeFees(
        uint256 baseFeesValue,
        uint256 distributionAmount,
        address rewardToken
    ) internal returns (uint256 distributionAmountMinusFees) {
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
    }

    /// @notice Internal version of the `sign` function
    function _sign(bytes calldata signature) internal {
        bytes32 _messageHash = messageHash;
        if (ECDSA.recover(_messageHash, signature) != msg.sender) revert InvalidSignature();
        userSignatures[msg.sender] = _messageHash;
        emit UserSigned(_messageHash, msg.sender);
    }

    /// @notice Rounds an `epoch` timestamp to the start of the corresponding period
    function _getRoundedEpoch(uint32 epoch) internal pure returns (uint32) {
        return (epoch / HOUR) * HOUR;
    }

    /// @notice Internal version of `getCampaignsBetween`
    function _getCampaignsBetween(
        uint32 start,
        uint32 end,
        uint32 skip,
        uint32 first
    ) internal view returns (CampaignParameters[] memory, uint256) {
        uint256 length;
        uint256 campaignListLength = campaignList.length;
        uint256 returnSize = first > campaignListLength ? campaignListLength : first;
        CampaignParameters[] memory activeRewards = new CampaignParameters[](returnSize);
        uint32 i = skip;
        while (i < campaignListLength) {
            CampaignParameters memory campaignToProcess = campaignList[i];
            if (
                campaignToProcess.startTimestamp + campaignToProcess.duration > start &&
                campaignToProcess.startTimestamp < end
            ) {
                activeRewards[length] = campaignToProcess;
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

    /// @notice Internal version of `getDistributionsBetweenEpochs`
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
            DistributionParameters memory d = distributionList[i];
            if (d.epochStart + d.numEpoch * HOUR > epochStart && d.epochStart < epochEnd) {
                activeRewards[length] = d;
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

    /// @notice Builds the list of valid reward tokens
    function _getValidRewardTokens(
        uint32 skip,
        uint32 first
    ) internal view returns (RewardTokenAmounts[] memory, uint256) {
        uint256 length;
        uint256 rewardTokenListLength = rewardTokens.length;
        uint256 returnSize = first > rewardTokenListLength ? rewardTokenListLength : first;
        RewardTokenAmounts[] memory validRewardTokens = new RewardTokenAmounts[](returnSize);
        uint32 i = skip;
        while (i < rewardTokenListLength) {
            address token = rewardTokens[i];
            uint256 minAmount = rewardTokenMinAmounts[token];
            if (minAmount > 0) {
                validRewardTokens[length] = RewardTokenAmounts(token, minAmount);
                length += 1;
            }
            unchecked {
                ++i;
            }
            if (length == returnSize) break;
        }
        assembly {
            mstore(validRewardTokens, length)
        }
        return (validRewardTokens, i);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[33] private __gap;
}
