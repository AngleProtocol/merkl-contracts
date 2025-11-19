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
/// @notice Manages the creation and administration of reward distribution campaigns through the Merkl system
/// @dev This contract serves as the primary interface for campaign creators and provides helper functions for APIs built on Merkl
/// @dev Deprecated variables are maintained in storage for upgrade compatibility
//solhint-disable
contract DistributionCreator is UUPSHelper, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 CONSTANTS / VARIABLES                                              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Duration of one hour in seconds
    uint32 public constant HOUR = 3600;

    /// @notice Base denominator for fee calculations (represents 100%)
    uint256 public constant BASE_9 = 1e9;

    /// @notice Chain ID where this contract is deployed
    uint256 public immutable CHAIN_ID = block.chainid;

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    /// @notice Address of the Distributor contract that distributes rewards to users
    address public distributor;

    /// @notice Address that receives protocol fees from campaign creation
    address public feeRecipient;

    /// @notice Default fee rate (in base 10^9) applied when creating a campaign
    uint256 public defaultFees;

    /// @notice Terms and conditions message that users must acknowledge before creating campaigns
    string public message;

    /// @notice Keccak256 hash of the conditions that users must accept before creating campaigns
    /// @dev The message may be a link to the full terms hosted offchain
    bytes32 public messageHash;

    /// @notice Deprecated - kept for storage layout compatibility
    DistributionParameters[] public distributionList;

    /// @notice Maps an address to its fee rebate percentage
    mapping(address => uint256) public feeRebate;

    /// @notice Deprecated - kept for storage layout compatibility
    mapping(address => uint256) public isWhitelistedToken;

    /// @notice Deprecated - kept for storage layout compatibility
    mapping(address => uint256) public _nonces;

    /// @notice Maps user addresses to the hash of the last terms and conditions they accepted
    /// @dev The name includes 'signature' for legacy reasons, reflecting the original requirement for users to sign conditions
    mapping(address => bytes32) public userSignatures;

    /// @notice Maps user addresses to their whitelist status for signature requirements
    /// @dev The name includes 'signature' for legacy reasons, reflecting the original requirement for users to sign conditions
    mapping(address => uint256) public userSignatureWhitelist;

    /// @notice Maps each reward token to its minimum required amount per epoch for campaign validity
    /// @dev A value of 0 indicates the token is not whitelisted and cannot be used as a reward
    mapping(address => uint256) public rewardTokenMinAmounts;

    /// @notice Array of all reward tokens that have been whitelisted at any point
    address[] public rewardTokens;

    /// @notice Array of all campaigns ever created in the contract (past, current, and future)
    /// @dev This list can grow unbounded, but is only accessed by view functions
    CampaignParameters[] public campaignList;

    /// @notice Maps a campaign ID to its index in the campaign list plus one (0 = does not exist)
    mapping(bytes32 => uint256) internal _campaignLookup;

    /// @notice Maps campaign types to their specific fee rates, overriding the default fee
    mapping(uint32 => uint256) public campaignSpecificFees;

    /// @notice Maps campaign IDs to override parameters that modify the original campaign
    mapping(bytes32 => CampaignParameters) public campaignOverrides;

    /// @notice Maps campaign IDs to timestamps when overrides were applied
    mapping(bytes32 => uint256[]) public campaignOverridesTimestamp;

    /// @notice Maps campaign IDs to reward reallocations (from address -> to address)
    mapping(bytes32 => mapping(address => address)) public campaignReallocation;

    /// @notice Maps campaign IDs to lists of addresses whose rewards have been reallocated
    mapping(bytes32 => address[]) public campaignListReallocation;

    /// @notice Maps creator addresses to their predeposited token balances for each reward token
    mapping(address => mapping(address => uint256)) public creatorBalance;

    /// @notice Maps creator addresses to operator approvals for spending predeposited tokens
    /// @dev creator => operator => rewardToken => allowance amount
    mapping(address => mapping(address => mapping(address => uint256))) public creatorAllowance;

    /// @notice Maps manager addresses to authorized campaign operators who can manage campaigns on their behalf
    mapping(address => mapping(address => uint256)) public campaignOperators;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    event CreatorAllowanceUpdated(address indexed user, address indexed operator, address indexed token, uint256 amount);
    event CreatorBalanceUpdated(address indexed user, address indexed token, uint256 amount);
    event DistributorUpdated(address indexed _distributor);
    event FeeRebateUpdated(address indexed user, uint256 userFeeRebate);
    event FeeRecipientUpdated(address indexed _feeRecipient);
    event FeesSet(uint256 _fees);
    event CampaignOperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);
    event CampaignOverride(bytes32 _campaignId, CampaignParameters campaign);
    event CampaignReallocation(bytes32 _campaignId, address[] indexed from, address indexed to);
    event CampaignSpecificFeesSet(uint32 campaignType, uint256 _fees);
    event MessageUpdated(bytes32 _messageHash);
    event NewCampaign(CampaignParameters campaign);
    event RewardTokenMinimumAmountUpdated(address indexed token, uint256 amount);
    event UserSigningWhitelistToggled(address indexed user, uint256 toggleStatus);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to addresses with governor or guardian role
    modifier onlyGovernorOrGuardian() {
        if (!accessControlManager.isGovernorOrGuardian(msg.sender)) revert Errors.NotGovernorOrGuardian();
        _;
    }

    /// @notice Restricts function access to addresses with governor role only
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /// @notice Ensures the caller has accepted the current terms or is whitelisted for this
    /// @dev Checks both msg.sender and tx.origin for signature or whitelist status
    modifier hasSigned() {
        if (
            userSignatureWhitelist[msg.sender] == 0 &&
            userSignatureWhitelist[tx.origin] == 0 &&
            userSignatures[msg.sender] != messageHash &&
            userSignatures[tx.origin] != messageHash
        ) revert Errors.NotSigned();
        _;
    }

    /// @notice Restricts function access to the specified user or any governor
    /// @param user The user address allowed to call the function
    modifier onlyUserOrGovernor(address user) {
        if (user != msg.sender && !accessControlManager.isGovernor(msg.sender)) revert Errors.NotAllowed();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with access control, distributor, and default fees
    /// @param _accessControlManager Address of the access control manager contract
    /// @param _distributor Address of the Distributor contract
    /// @param _fees Default fee rate in base 10^9 (must be less than BASE_9)
    function initialize(IAccessControlManager _accessControlManager, address _distributor, uint256 _fees) external initializer {
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

    /// @notice Creates a new reward distribution campaign
    /// @param newCampaign Parameters defining the campaign structure and rewards
    /// @return campaignId Unique identifier for the newly created campaign
    /// @dev Campaigns with invalid formatting may not be processed by the reward engine, potentially losing rewards
    /// @dev Reward tokens must be whitelisted and amounts must exceed the token-specific minimum threshold
    /// @dev Reverts if the sender has not accepted the terms and conditions via acceptConditions() or signature
    function createCampaign(CampaignParameters memory newCampaign) external nonReentrant hasSigned returns (bytes32) {
        return _createCampaign(newCampaign);
    }

    /// @notice Creates multiple reward distribution campaigns in a single transaction
    /// @param campaigns Array of campaign parameters to create
    /// @return Array of campaign IDs for all newly created campaigns
    function createCampaigns(CampaignParameters[] memory campaigns) external nonReentrant hasSigned returns (bytes32[] memory) {
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

    /// @notice Allows a user to accept Merkl's terms and conditions to enable campaign creation
    /// @dev If the conditions change (through setMessage), users must accept again the new terms
    /// @dev If the messageHash is not set, it means that there are no conditions to accept
    function acceptConditions() external {
        userSignatures[msg.sender] = messageHash;
    }

    /// @notice Updates parameters of an existing campaign while preserving core immutable fields
    /// @param _campaignId ID of the campaign to override
    /// @param newCampaign New campaign parameters (some fields will be ignored or validated)
    /// @dev Cannot change rewardToken, amount, or creator address
    /// @dev Can only update startTimestamp if the campaign has not yet started
    /// @dev New end time (startTimestamp + duration) must be in the future
    /// @dev The Merkl engine validates override correctness; invalid overrides are ignored
    /// @dev In the case of an invalid override, the campaign may not be processed and fees may still be taken by the Merkl engine
    function overrideCampaign(bytes32 _campaignId, CampaignParameters memory newCampaign) external {
        CampaignParameters memory _campaign = campaign(_campaignId);
        _isValidOperator(_campaign.creator);
        if (
            newCampaign.rewardToken != _campaign.rewardToken ||
            newCampaign.amount != _campaign.amount ||
            (newCampaign.startTimestamp != _campaign.startTimestamp && block.timestamp > _campaign.startTimestamp) || // Allow to update startTimestamp before campaign start
            // End timestamp should be in the future
            newCampaign.duration + _campaign.startTimestamp <= block.timestamp
        ) revert Errors.InvalidOverride();

        newCampaign.campaignId = _campaignId;
        // The manager address cannot be changed
        newCampaign.creator = _campaign.creator;
        campaignOverrides[_campaignId] = newCampaign;
        campaignOverridesTimestamp[_campaignId].push(block.timestamp);
        emit CampaignOverride(_campaignId, newCampaign);
    }

    /// @notice Reallocates unclaimed rewards from specific addresses to a new recipient after campaign ends
    /// @param _campaignId ID of the completed campaign to reallocate from
    /// @param froms Array of addresses whose unclaimed rewards should be reallocated
    /// @param to Address that will receive the reallocated rewards
    /// @dev Can only be called after the campaign has ended (startTimestamp + duration has passed)
    /// @dev Reallocation validity is determined by the Merkl engine; invalid reallocations are ignored
    function reallocateCampaignRewards(bytes32 _campaignId, address[] memory froms, address to) external {
        CampaignParameters memory _campaign = campaign(_campaignId);
        _isValidOperator(_campaign.creator);
        if (block.timestamp < _campaign.startTimestamp + _campaign.duration) revert Errors.InvalidReallocation();

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

    /// @notice Increases a user's predeposited token balance for campaign funding
    /// @param user Address whose balance will be increased
    /// @param rewardToken Token to deposit
    /// @param amount Amount to deposit
    /// @dev When called by a governor, the user must have sent tokens to the contract beforehand
    /// @dev Can be used to deposit on behalf of another user
    /// @dev WARNING: Do not use with any non strictly standard ERC20 (like rebasing tokens) as they will cause accounting issues
    function increaseTokenBalance(address user, address rewardToken, uint256 amount) external {
        if (!accessControlManager.isGovernor(msg.sender)) IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        _updateBalance(user, rewardToken, creatorBalance[user][rewardToken] + amount);
    }

    /// @notice Decreases a user's predeposited token balance and transfers tokens out
    /// @param user Address whose balance will be decreased
    /// @param rewardToken Token to withdraw
    /// @param to Address that will receive the withdrawn tokens
    /// @param amount Amount to withdraw
    /// @dev Only callable by the user themselves or a governor
    function decreaseTokenBalance(address user, address rewardToken, address to, uint256 amount) external onlyUserOrGovernor(user) {
        _updateBalance(user, rewardToken, creatorBalance[user][rewardToken] - amount);
        IERC20(rewardToken).safeTransfer(to, amount);
    }

    /// @notice Increases an operator's allowance to spend a user's predeposited tokens
    /// @param user User granting the allowance
    /// @param operator Operator receiving spending permission
    /// @param rewardToken Token for which allowance is granted
    /// @param amount Amount to increase the allowance by
    /// @dev Only callable by the user themselves or a governor
    function increaseTokenAllowance(address user, address operator, address rewardToken, uint256 amount) external onlyUserOrGovernor(user) {
        _updateAllowance(user, operator, rewardToken, creatorAllowance[user][operator][rewardToken] + amount);
    }

    /// @notice Decreases an operator's allowance to spend a user's predeposited tokens
    /// @param user User reducing the allowance
    /// @param operator Operator whose allowance is being reduced
    /// @param rewardToken Token for which allowance is reduced
    /// @param amount Amount to decrease the allowance by
    /// @dev Only callable by the user themselves or a governor
    function decreaseTokenAllowance(address user, address operator, address rewardToken, uint256 amount) external onlyUserOrGovernor(user) {
        _updateAllowance(user, operator, rewardToken, creatorAllowance[user][operator][rewardToken] - amount);
    }

    /// @notice Toggles an operator's authorization to create and manage campaigns on behalf of a user
    /// @param user User granting or revoking operator access
    /// @param operator Operator whose authorization is being toggled
    /// @dev Only callable by the user themselves or a governor
    /// @dev Toggles between authorized (1) and unauthorized (0)
    function toggleCampaignOperator(address user, address operator) external onlyUserOrGovernor(user) {
        uint256 currentStatus = campaignOperators[user][operator];
        campaignOperators[user][operator] = 1 - currentStatus;
        emit CampaignOperatorToggled(user, operator, currentStatus == 0);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the array index of a campaign in the campaign list
    /// @param _campaignId ID of the campaign to look up
    /// @return Zero-based index of the campaign in the campaignList array
    /// @dev Reverts if the campaign does not exist
    function campaignLookup(bytes32 _campaignId) public view returns (uint256) {
        uint256 index = _campaignLookup[_campaignId];
        if (index == 0) revert Errors.CampaignDoesNotExist();
        return index - 1;
    }

    /// @notice Returns the original parameters of a campaign
    /// @param _campaignId ID of the campaign to retrieve
    /// @return Campaign parameters as originally created
    /// @dev Returns original parameters even if the campaign has been overridden
    function campaign(bytes32 _campaignId) public view returns (CampaignParameters memory) {
        return campaignList[campaignLookup(_campaignId)];
    }

    /// @notice Computes the unique campaign ID for a given set of campaign parameters
    /// @param campaignData Campaign parameters to hash
    /// @return Unique campaign ID derived from hashing key parameters
    /// @dev Campaign ID is computed as keccak256 of creator, rewardToken, campaignType, startTimestamp, duration, and campaignData
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

    /// @notice Returns all whitelisted reward tokens and their minimum required amounts
    /// @return Array of reward tokens with their minimum amounts per epoch
    /// @dev Not optimized for onchain queries; intended for off-chain/API use
    function getValidRewardTokens() external view returns (RewardTokenAmounts[] memory) {
        (RewardTokenAmounts[] memory validRewardTokens, ) = _getValidRewardTokens(0, type(uint32).max);
        return validRewardTokens;
    }

    /// @notice Returns a paginated list of whitelisted reward tokens
    /// @param skip Number of tokens to skip
    /// @param first Maximum number of tokens to return
    /// @return Array of reward tokens and total count
    /// @dev Not optimized for onchain queries; intended for off-chain/API use
    function getValidRewardTokens(uint32 skip, uint32 first) external view returns (RewardTokenAmounts[] memory, uint256) {
        return _getValidRewardTokens(skip, first);
    }

    /// @notice Returns all timestamps when a campaign was overridden
    /// @param _campaignId ID of the campaign
    /// @return Array of block timestamps when overrides occurred
    function getCampaignOverridesTimestamp(bytes32 _campaignId) external view returns (uint256[] memory) {
        return campaignOverridesTimestamp[_campaignId];
    }

    /// @notice Returns all addresses from which rewards were reallocated for a campaign
    /// @param _campaignId ID of the campaign
    /// @return Array of addresses that had rewards reallocated away from them
    function getCampaignListReallocation(bytes32 _campaignId) external view returns (address[] memory) {
        return campaignListReallocation[_campaignId];
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GOVERNANCE FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the Distributor contract address that receives and distributes rewards
    /// @param _distributor New Distributor contract address
    /// @dev Only callable by governor
    function setNewDistributor(address _distributor) external onlyGovernor {
        if (_distributor == address(0)) revert Errors.InvalidParam();
        distributor = _distributor;
        emit DistributorUpdated(_distributor);
    }

    /// @notice Withdraws accumulated protocol fees to a specified address
    /// @param tokens Array of token addresses to withdraw fees from
    /// @param to Address that will receive the withdrawn fees
    /// @dev Only callable by governor
    /// @dev Transfers the entire balance of each token held by the contract
    function recoverFees(IERC20[] calldata tokens, address to) external onlyGovernor {
        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength; ) {
            tokens[i].safeTransfer(to, tokens[i].balanceOf(address(this)));
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Updates the address that receives protocol fees from campaign creation
    /// @param _feeRecipient New fee recipient address
    /// @dev Only callable by governor
    function setFeeRecipient(address _feeRecipient) external onlyGovernor {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /// @notice Updates the terms and conditions that users must accept before creating campaigns
    /// @param _message New terms and conditions message text
    /// @dev Only callable by governor or guardian
    /// @dev Automatically computes and stores the keccak256 hash
    /// @dev The message may be a link to the full terms hosted offchain
    function setMessage(string memory _message) external onlyGovernorOrGuardian {
        message = _message;
        bytes32 _messageHash = ECDSA.toEthSignedMessageHash(bytes(_message));
        messageHash = _messageHash;
        emit MessageUpdated(_messageHash);
    }

    /// @notice Updates the default fee rate applied to campaign creation
    /// @param _defaultFees New default fee rate in base 10^9
    /// @dev Only callable by governor or guardian
    /// @dev Fee rate must be less than BASE_9 (100%)
    function setFees(uint256 _defaultFees) external onlyGovernorOrGuardian {
        if (_defaultFees >= BASE_9) revert Errors.InvalidParam();
        defaultFees = _defaultFees;
        emit FeesSet(_defaultFees);
    }

    /// @notice Sets campaign-type-specific fee rates that override the default fee
    /// @param campaignType Type identifier for the campaign
    /// @param _fees Fee rate for this campaign type in base 10^9
    /// @dev Only callable by governor or guardian
    /// @dev Set fee to 1 to effectively waive fees for a campaign type
    /// @dev Fee rate must be less than BASE_9 (100%)
    function setCampaignFees(uint32 campaignType, uint256 _fees) external onlyGovernorOrGuardian {
        if (_fees >= BASE_9) revert Errors.InvalidParam();
        campaignSpecificFees[campaignType] = _fees;
        emit CampaignSpecificFeesSet(campaignType, _fees);
    }

    /// @notice Sets a fee rebate for a specific user
    /// @param user User address receiving the fee rebate
    /// @param userFeeRebate Rebate amount in base 10^9
    /// @dev Only callable by governor or guardian
    function setUserFeeRebate(address user, uint256 userFeeRebate) external onlyGovernorOrGuardian {
        feeRebate[user] = userFeeRebate;
        emit FeeRebateUpdated(user, userFeeRebate);
    }

    /// @notice Toggles whether a user must sign the terms message before creating campaigns
    /// @param user User address whose whitelist status is being toggled
    /// @dev Only callable by governor or guardian
    /// @dev Whitelisted users (status = 1) can create campaigns without accepting Merkl terms
    function toggleSigningWhitelist(address user) external onlyGovernorOrGuardian {
        uint256 whitelistStatus = 1 - userSignatureWhitelist[user];
        userSignatureWhitelist[user] = whitelistStatus;
        emit UserSigningWhitelistToggled(user, whitelistStatus);
    }

    /// @notice Configures minimum reward amounts per epoch for whitelisted tokens
    /// @param tokens Array of reward token addresses
    /// @param amounts Array of minimum amounts (0 = remove from whitelist, >0 = add/update)
    /// @dev Only callable by governor or guardian
    /// @dev Setting amount to 0 effectively removes the token from the whitelist
    /// @dev Prevents duplicate entries when adding previously removed tokens
    function setRewardTokenMinAmounts(address[] calldata tokens, uint256[] calldata amounts) external onlyGovernorOrGuardian {
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

    /// @notice Internal function to create a new campaign with validation and fee processing
    /// @param newCampaign Campaign parameters to create
    /// @return Unique campaign ID of the created campaign
    /// @dev Validates campaign duration, reward token whitelist status, and minimum reward amounts
    /// @dev Computes and deducts protocol fees from the campaign amount
    /// @dev Reverts if campaign already exists or validation fails
    function _createCampaign(CampaignParameters memory newCampaign) internal returns (bytes32) {
        uint256 rewardTokenMinAmount = rewardTokenMinAmounts[newCampaign.rewardToken];
        // if the campaign doesn't last at least one hour
        if (newCampaign.duration < HOUR) revert Errors.CampaignDurationBelowHour();
        // if the reward token is not whitelisted as an incentive token
        if (rewardTokenMinAmount == 0) revert Errors.CampaignRewardTokenNotWhitelisted();
        // if the amount distributed is too small with respect to what is allowed
        if ((newCampaign.amount * HOUR) / newCampaign.duration < rewardTokenMinAmount) revert Errors.CampaignRewardTooLow();
        // Computing fees and pulling tokens
        uint256 campaignAmountMinusFees = _computeFees(newCampaign.campaignType, newCampaign.amount);
        if (newCampaign.creator == address(0)) newCampaign.creator = msg.sender;
        _pullTokens(newCampaign.creator, newCampaign.rewardToken, newCampaign.amount, campaignAmountMinusFees);
        newCampaign.amount = campaignAmountMinusFees;
        newCampaign.campaignId = campaignId(newCampaign);

        if (_campaignLookup[newCampaign.campaignId] != 0) revert Errors.CampaignAlreadyExists();
        _campaignLookup[newCampaign.campaignId] = campaignList.length + 1;
        campaignList.push(newCampaign);
        emit NewCampaign(newCampaign);

        return newCampaign.campaignId;
    }

    /// @notice Validates that the caller is authorized to manage campaigns for the specified manager
    /// @param manager Address of the campaign manager
    /// @dev Reverts if msg.sender is not the manager and not an authorized operator
    function _isValidOperator(address manager) internal view {
        if (manager != msg.sender && campaignOperators[manager][msg.sender] == 0) {
            revert Errors.OperatorNotAllowed();
        }
    }

    /// @notice Updates an operator's allowance to spend a user's predeposited tokens
    /// @param user User granting the allowance
    /// @param operator Operator receiving the allowance
    /// @param rewardToken Token for which allowance is being set
    /// @param newAllowance New allowance amount
    function _updateAllowance(address user, address operator, address rewardToken, uint256 newAllowance) internal {
        creatorAllowance[user][operator][rewardToken] = newAllowance;
        emit CreatorAllowanceUpdated(user, operator, rewardToken, newAllowance);
    }

    /// @notice Updates a user's predeposited token balance
    /// @param user User whose balance is being updated
    /// @param rewardToken Token whose balance is being updated
    /// @param newBalance New balance amount
    function _updateBalance(address user, address rewardToken, uint256 newBalance) internal {
        creatorBalance[user][rewardToken] = newBalance;
        emit CreatorBalanceUpdated(user, rewardToken, newBalance);
    }

    /// @notice Transfers reward tokens from creator's balance or msg.sender to the distributor
    /// @param creator Address of the campaign creator
    /// @param rewardToken Token being transferred
    /// @param campaignAmount Total amount including fees
    /// @param campaignAmountMinusFees Net amount after fees to send to distributor
    /// @dev Attempts to use predeposited balance first, checking operator allowance if applicable
    /// @dev Falls back to direct transfer from msg.sender if insufficient predeposited balance
    /// @dev Sends fees to feeRecipient (or this contract if feeRecipient is zero address)
    function _pullTokens(address creator, address rewardToken, uint256 campaignAmount, uint256 campaignAmountMinusFees) internal {
        uint256 fees = campaignAmount - campaignAmountMinusFees;
        address _feeRecipient;
        if (fees > 0) {
            _feeRecipient = feeRecipient;
            _feeRecipient = _feeRecipient == address(0) ? address(this) : _feeRecipient;
        }
        uint256 userBalance = creatorBalance[creator][rewardToken];
        if (userBalance >= campaignAmount) {
            if (msg.sender != creator) {
                uint256 senderAllowance = creatorAllowance[creator][msg.sender][rewardToken];
                if (senderAllowance >= campaignAmount) {
                    _updateAllowance(creator, msg.sender, rewardToken, senderAllowance - campaignAmount);
                } else {
                    if (fees > 0) IERC20(rewardToken).safeTransferFrom(msg.sender, _feeRecipient, fees);
                    IERC20(rewardToken).safeTransferFrom(msg.sender, distributor, campaignAmountMinusFees);
                    return;
                }
            }
            _updateBalance(creator, rewardToken, userBalance - campaignAmount);
            if (fees > 0 && _feeRecipient != address(this)) IERC20(rewardToken).safeTransfer(_feeRecipient, fees);
            IERC20(rewardToken).safeTransfer(distributor, campaignAmountMinusFees);
        } else {
            if (fees > 0) IERC20(rewardToken).safeTransferFrom(msg.sender, _feeRecipient, fees);
            IERC20(rewardToken).safeTransferFrom(msg.sender, distributor, campaignAmountMinusFees);
        }
    }

    /// @notice Calculates the net campaign amount after deducting applicable fees
    /// @param campaignType Type of campaign for fee calculation
    /// @param distributionAmount Gross distribution amount before fees
    /// @return distributionAmountMinusFees Net amount after fees are deducted
    /// @dev Uses campaign-specific fees if set, otherwise uses default fees
    /// @dev Campaign-specific fee of 1 is treated as 0 (fee waiver)
    /// @dev Applies fee rebates to msg.sender (not creator)
    function _computeFees(uint32 campaignType, uint256 distributionAmount) internal view returns (uint256 distributionAmountMinusFees) {
        uint256 baseFeesValue = campaignSpecificFees[campaignType];
        if (baseFeesValue == 1) baseFeesValue = 0;
        else if (baseFeesValue == 0) baseFeesValue = defaultFees;
        // Fee rebates are applied to the msg.sender and not to the creator of the campaign
        uint256 _fees = (baseFeesValue * (BASE_9 - feeRebate[msg.sender])) / BASE_9;
        distributionAmountMinusFees = distributionAmount;
        if (_fees != 0) {
            distributionAmountMinusFees = (distributionAmount * (BASE_9 - _fees)) / BASE_9;
        }
    }

    /// @notice Builds a paginated list of whitelisted reward tokens with their minimum amounts
    /// @param skip Number of tokens to skip in the iteration
    /// @param first Maximum number of tokens to return
    /// @return Array of valid reward tokens and the index where iteration stopped
    /// @dev Only includes tokens with non-zero minimum amounts (active whitelist entries)
    /// @dev Uses assembly to resize the return array to actual length
    function _getValidRewardTokens(uint32 skip, uint32 first) internal view returns (RewardTokenAmounts[] memory, uint256) {
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
    uint256[28] private __gap;
}
