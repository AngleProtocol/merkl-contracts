// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { UUPSHelper } from "./utils/UUPSHelper.sol";
import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";
import { Errors } from "./utils/Errors.sol";
import { CampaignParameters } from "./struct/CampaignParameters.sol";
import { DistributionParameters } from "./struct/DistributionParameters.sol";
import { RewardTokenAmounts } from "./struct/RewardTokenAmounts.sol";

/// @title DistributionCreator
/// @author Merkl SAS
/// @notice Manages the distribution of rewards through the Merkl system
/// @dev This contract is mostly a helper for APIs built on top of Merkl
/// @dev The deprecated variables in this contract are kept for storage layout compatibility
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

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    /// @notice Contract distributing rewards to users
    address public distributor;

    /// @notice Address to which fees are forwarded
    address public feeRecipient;

    /// @notice Value (in base 10**9) of the fees taken when creating a campaign
    uint256 public defaultFees;

    /// @notice Message that needs to be acknowledged by users creating a campaign
    string public message;

    /// @notice Hash of the message that needs to be signed or accepted
    bytes32 public messageHash;

    /// @notice Deprecated
    DistributionParameters[] public distributionList;

    /// @notice Maps an address to its fee rebate
    mapping(address => uint256) public feeRebate;

    /// @notice Deprecated
    mapping(address => uint256) public isWhitelistedToken;

    /// @notice Deprecated
    mapping(address => uint256) public _nonces;

    /// @notice Deprecated
    mapping(address => bytes32) public userSignatures;

    /// @notice Deprecated
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

    /// @notice Maps a campaignId to a potential override written
    mapping(bytes32 => CampaignParameters) public campaignOverrides;

    /// @notice Maps a campaignId to the block numbers at which it's been updated
    mapping(bytes32 => uint256[]) public campaignOverridesTimestamp;

    /// @notice Maps one address to another one to reallocate rewards for a given campaign
    mapping(bytes32 => mapping(address => address)) public campaignReallocation;

    /// @notice List all reallocated address for a given campaign
    mapping(bytes32 => address[]) public campaignListReallocation;

    /// @notice Maps a creator address to an operator to a reward token to an amount that can be pulled from the creator
    mapping(address => mapping(address => mapping(address => uint256))) public creatorTokenAllowance;

    /// @notice Maps a creator to a campaign operator to the ability to manage the campaign on behalf of the creator
    mapping(address => mapping(address => uint256)) public creatorCampaignOperators;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    event CreatorAllowanceUpdated(
        address indexed user,
        address indexed operator,
        address indexed token,
        uint256 amount
    );
    event DistributorUpdated(address indexed _distributor);
    event FeeRebateUpdated(address indexed user, uint256 userFeeRebate);
    event FeeRecipientUpdated(address indexed _feeRecipient);
    event FeesSet(uint256 _fees);
    event CampaignOverride(bytes32 _campaignId, CampaignParameters campaign);
    event CampaignReallocation(bytes32 _campaignId, address[] indexed from, address indexed to);
    event CampaignSpecificFeesSet(uint32 campaignType, uint256 _fees);
    event MessageUpdated(bytes32 _messageHash);
    event NewCampaign(CampaignParameters campaign);
    event RewardTokenMinimumAmountUpdated(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!accessControlManager.isGovernorOrGuardian(msg.sender)) revert Errors.NotGovernorOrGuardian();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /// @notice Checks whether an address has signed the message or not
    modifier hasSigned() {
        if (
            userSignatureWhitelist[msg.sender] == 0 &&
            userSignatureWhitelist[tx.origin] == 0 &&
            userSignatures[msg.sender] != messageHash &&
            userSignatures[tx.origin] != messageHash
        ) revert Errors.NotSigned();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function initialize(
        IAccessControlManager _accessControlManager,
        address _distributor,
        uint256 _fees
    ) external initializer {
        if (address(_accessControlManager) == address(0) || _distributor == address(0)) revert Errors.ZeroAddress();
        if (_fees >= BASE_9) revert Errors.InvalidParam();
        distributor = _distributor;
        accessControlManager = _accessControlManager;
        defaultFees = _fees;
    }

    constructor() initializer {}

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(accessControlManager) {}

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

    /// @notice Allows a user to accept the Merkl conditions (expressed in the messageHash) in order to start their campaigns
    function acceptConditions() external {
        userSignatureWhitelist[msg.sender] = 1;
    }

    /// @notice Overrides a campaign with new parameters
    /// @dev Some overrides maybe incorrect, but their correctness cannot be checked onchain. It is up to the Merkl
    /// engine to check the validity of the override. If the override is invalid, then the first campaign details
    /// will still apply.
    /// @dev Some fields in the new campaign parameters will be disregarded anyway (like the amount)
    function overrideCampaign(bytes32 _campaignId, CampaignParameters memory newCampaign) external {
        CampaignParameters memory _campaign = campaign(_campaignId);
        if (
            _campaign.creator != msg.sender ||
            newCampaign.rewardToken != _campaign.rewardToken ||
            newCampaign.amount != _campaign.amount ||
            (newCampaign.startTimestamp != _campaign.startTimestamp && block.timestamp > _campaign.startTimestamp) || // Allow to update startTimestamp before campaign start
            // End timestamp should be in the future
            newCampaign.duration + _campaign.startTimestamp <= block.timestamp
        ) revert Errors.InvalidOverride();

        newCampaign.campaignId = _campaignId;
        newCampaign.creator = msg.sender;
        campaignOverrides[_campaignId] = newCampaign;
        campaignOverridesTimestamp[_campaignId].push(block.timestamp);
        emit CampaignOverride(_campaignId, newCampaign);
    }

    /// @notice Reallocates rewards of a given campaign from one address to another
    /// @dev While this function may execute successfully, the reallocation may not be valid in the Merkl engine
    function reallocateCampaignRewards(bytes32 _campaignId, address[] memory froms, address to) external {
        CampaignParameters memory _campaign = campaign(_campaignId);
        if (_campaign.creator != msg.sender || block.timestamp < _campaign.startTimestamp + _campaign.duration)
            revert Errors.InvalidOverride();

        uint256 fromsLength = froms.length;
        for (uint256 i; i < fromsLength; ) {
            campaignReallocation[_campaignId][froms[i]] = to;
            campaignListReallocation[_campaignId].push(froms[i]);
            unchecked {
                ++i;
            }
        }
        emit CampaignReallocation(_campaignId, froms, to);
    }

    /// @dev If a governor address calls this function, the user MUST have transferred the funds to the contract beforehand
    function increaseCreatorTokenAllowance(
        address user,
        address operator,
        address rewardToken,
        uint256 amount
    ) external {
        if (operator == address(0)) revert Errors.ZeroAddress();
        if (user == msg.sender) IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        else if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();

        uint256 currentAllowance = creatorTokenAllowance[user][operator][rewardToken];
        creatorTokenAllowance[user][operator][rewardToken] = currentAllowance + amount;
        emit CreatorAllowanceUpdated(user, operator, rewardToken, currentAllowance + amount);
    }

    function decreaseCreatorTokenAllowance(
        address user,
        address operator,
        address rewardToken,
        uint256 amount
    ) external {
        if (operator == address(0)) revert Errors.ZeroAddress();
        uint256 currentAllowance = creatorTokenAllowance[user][operator][rewardToken];
        uint256 updateAmount = amount > currentAllowance ? currentAllowance : amount;
        creatorTokenAllowance[user][operator][rewardToken] = currentAllowance - updateAmount;
        if (user == msg.sender) IERC20(rewardToken).safeTransfer(msg.sender, updateAmount);
        else if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();

        emit CreatorAllowanceUpdated(user, operator, rewardToken, currentAllowance - updateAmount);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the index of a campaign in the campaign list
    function campaignLookup(bytes32 _campaignId) public view returns (uint256) {
        uint256 index = _campaignLookup[_campaignId];
        if (index == 0) revert Errors.CampaignDoesNotExist();
        return index - 1;
    }

    /// @notice Returns the campaign parameters of a given campaignId
    /// @dev If a campaign has been overriden, this function still shows the original state of the campaign
    function campaign(bytes32 _campaignId) public view returns (CampaignParameters memory) {
        return campaignList[campaignLookup(_campaignId)];
    }

    /// @notice Returns the campaign ID for a given campaign
    /// @dev The campaign ID is computed as the hash of various parameters
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

    /// @notice Gets the list of timestamps for when a campaign was overridden
    function getCampaignOverridesTimestamp(bytes32 _campaignId) external view returns (uint256[] memory) {
        return campaignOverridesTimestamp[_campaignId];
    }

    /// @notice Gets the list of addresses from which rewards were reallocated for a given campaign
    function getCampaignListReallocation(bytes32 _campaignId) external view returns (address[] memory) {
        return campaignListReallocation[_campaignId];
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GOVERNANCE FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets a new `distributor` to which rewards should be distributed
    function setNewDistributor(address _distributor) external onlyGovernor {
        if (_distributor == address(0)) revert Errors.InvalidParam();
        distributor = _distributor;
        emit DistributorUpdated(_distributor);
    }

    /// @notice Sets the defaultFees on deposit
    function setFees(uint256 _defaultFees) external onlyGovernor {
        if (_defaultFees >= BASE_9) revert Errors.InvalidParam();
        defaultFees = _defaultFees;
        emit FeesSet(_defaultFees);
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

    /// @notice Sets a new address to receive fees
    function setFeeRecipient(address _feeRecipient) external onlyGovernor {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /// @notice Sets the message that needs to be accepted by users before posting rewards
    function setMessage(string memory _message) external onlyGovernor {
        message = _message;
        bytes32 _messageHash = ECDSA.toEthSignedMessageHash(bytes(_message));
        messageHash = _messageHash;
        emit MessageUpdated(_messageHash);
    }

    /// @notice Sets the fees specific for a campaign
    /// @dev To waive the fees for a campaign, set its fees to 1
    function setCampaignFees(uint32 campaignType, uint256 _fees) external onlyGovernorOrGuardian {
        if (_fees >= BASE_9) revert Errors.InvalidParam();
        campaignSpecificFees[campaignType] = _fees;
        emit CampaignSpecificFeesSet(campaignType, _fees);
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
        if (tokensLength != amounts.length) revert Errors.InvalidLengths();
        for (uint256 i; i < tokensLength; ) {
            uint256 amount = amounts[i];
            // Basic logic check to make sure there are no duplicates in the `rewardTokens` table. If a token is
            // removed then re-added, it will appear as a duplicate in the list
            if (amount != 0 && rewardTokenMinAmounts[tokens[i]] == 0) rewardTokens.push(tokens[i]);
            rewardTokenMinAmounts[tokens[i]] = amount;
            emit RewardTokenMinimumAmountUpdated(tokens[i], amount);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       INTERNAL                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal version of `createCampaign`
    function _createCampaign(CampaignParameters memory newCampaign) internal returns (bytes32) {
        uint256 rewardTokenMinAmount = rewardTokenMinAmounts[newCampaign.rewardToken];
        // if the campaign doesn't last at least one hour
        if (newCampaign.duration < HOUR) revert Errors.CampaignDurationBelowHour();
        // if the reward token is not whitelisted as an incentive token
        if (rewardTokenMinAmount == 0) revert Errors.CampaignRewardTokenNotWhitelisted();
        // if the amount distributed is too small with respect to what is allowed
        if ((newCampaign.amount * HOUR) / newCampaign.duration < rewardTokenMinAmount)
            revert Errors.CampaignRewardTooLow();

        if (newCampaign.creator == address(0)) newCampaign.creator = msg.sender;

        // Computing fees: these are waived for whitelisted addresses and if there is a whitelisted token in a pool
        uint256 campaignAmountMinusFees = _computeFees(newCampaign.campaignType, newCampaign.amount);
        _pullTokens(newCampaign.creator, newCampaign.rewardToken, newCampaign.amount, campaignAmountMinusFees);
        newCampaign.amount = campaignAmountMinusFees;
        newCampaign.campaignId = campaignId(newCampaign);

        if (_campaignLookup[newCampaign.campaignId] != 0) revert Errors.CampaignAlreadyExists();
        _campaignLookup[newCampaign.campaignId] = campaignList.length + 1;
        campaignList.push(newCampaign);
        emit NewCampaign(newCampaign);

        return newCampaign.campaignId;
    }

    function _pullTokens(
        address creator,
        address rewardToken,
        uint256 campaignAmount,
        uint256 campaignAmountMinusFees
    ) internal {
        uint256 senderAllowance = creatorTokenAllowance[creator][msg.sender][rewardToken];
        uint256 fees = campaignAmount - campaignAmountMinusFees;
        address _feeRecipient = feeRecipient;
        _feeRecipient = _feeRecipient == address(0) ? address(this) : _feeRecipient;
        if (senderAllowance > campaignAmount) {
            creatorTokenAllowance[creator][msg.sender][rewardToken] = senderAllowance - campaignAmount;
            emit CreatorAllowanceUpdated(creator, msg.sender, rewardToken, senderAllowance - campaignAmount);
            if (fees > 0) IERC20(rewardToken).safeTransfer(_feeRecipient, fees);
            IERC20(rewardToken).safeTransfer(distributor, campaignAmountMinusFees);
        } else {
            if (fees > 0) IERC20(rewardToken).safeTransferFrom(msg.sender, _feeRecipient, fees);
            IERC20(rewardToken).safeTransferFrom(msg.sender, distributor, campaignAmountMinusFees);
        }
    }

    /// @notice Computes the fees to be taken on a campaign and transfers them to the fee recipient
    function _computeFees(
        uint32 campaignType,
        uint256 distributionAmount
    ) internal view returns (uint256 distributionAmountMinusFees) {
        uint256 baseFeesValue = campaignSpecificFees[campaignType];
        if (baseFeesValue == 1) baseFeesValue = 0;
        else if (baseFeesValue == 0) baseFeesValue = defaultFees;

        uint256 _fees = (baseFeesValue * (BASE_9 - feeRebate[msg.sender])) / BASE_9;
        distributionAmountMinusFees = distributionAmount;
        if (_fees != 0) {
            distributionAmountMinusFees = (distributionAmount * (BASE_9 - _fees)) / BASE_9;
        }
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
    uint256[31] private __gap;
}
