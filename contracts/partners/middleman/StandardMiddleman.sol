// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { DistributionCreator, CampaignParameters } from "../../DistributionCreator.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title StandardMiddleman
/// @author Angle Labs, Inc.
/// @notice Middleman contract enabling authorized executors to create Merkl incentive campaigns
/// @dev This contract allows whitelisted executors to trigger reward distributions by calling `notifyReward`.
/// The owner configures default campaign parameters, and executors can create campaigns with those parameters
/// by providing the reward amount. The contract handles token transfers and approvals automatically.
contract StandardMiddleman is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Default campaign parameters used when creating new campaigns
    /// @dev These parameters define the campaign type, duration, reward token, and distribution rules.
    /// Must be set by the owner before any campaign can be created.
    CampaignParameters public defaultParams;

    /// @notice Whitelist of addresses authorized to call `notifyReward`
    /// @dev A non-zero value indicates the address is authorized as an executor
    mapping(address => uint256) public executors;

    /// @notice Address of the Merkl DistributionCreator contract used to create campaigns
    /// @dev If set to address(0), defaults to the standard Merkl deployment address
    address public distributionCreator;

    /// @notice Offset in seconds subtracted from block.timestamp to determine campaign start time
    /// @dev Allows creating retroactive campaigns. Stored as uint96 to pack with distributionCreator address
    uint96 public startTimestampOffset;

    /// @notice Emitted when the default campaign parameters are updated
    /// @param params The new default campaign parameters
    event DefaultParametersSet(CampaignParameters params);

    /// @notice Emitted when the DistributionCreator address is updated
    /// @param _distributionCreator The new DistributionCreator contract address
    event DistributionCreatorSet(address indexed _distributionCreator);

    /// @notice Emitted when the start timestamp offset is updated
    /// @param _startTimestampOffset The new offset in seconds
    event StartTimestampOffsetSet(uint96 _startTimestampOffset);

    /// @notice Emitted when an executor's status is updated
    /// @param executor The address whose executor status was updated
    /// @param status The new status (non-zero for authorized, zero for revoked)
    event ExecutorSet(address indexed executor, uint256 status);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with an owner and DistributionCreator address
    /// @param _owner Address that will own the contract and manage parameters
    /// @param _distributionCreator Address of the Merkl DistributionCreator contract (can be address(0) to use default)
    constructor(address _owner, address _distributionCreator) {
        transferOwnership(_owner);
        DistributionCreator(_distributionCreator).acceptConditions();
        distributionCreator = _distributionCreator;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the DistributionCreator contract to use for campaign creation
    /// @dev Falls back to the default Merkl deployment address (0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd)
    /// if no custom address was set
    /// @return _distributionCreator The DistributionCreator contract instance
    function merklDistributionCreator() public view virtual returns (DistributionCreator _distributionCreator) {
        _distributionCreator = DistributionCreator(distributionCreator);
        if (address(_distributionCreator) == address(0)) return DistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
    }

    /*//////////////////////////////////////////////////////////////
                           EXECUTOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Merkl campaign with the specified reward amount
    /// @dev Only callable by whitelisted executors. The campaign uses the pre-configured default parameters.
    /// @dev The function will revert if the default parameters have not been set or if the amount to distribute is too small
    /// @dev Requires the tokens to to distribute to be held on this contract before calling
    /// @param amount The amount of reward tokens to distribute in the campaign
    function notifyReward(uint256 amount) public {
        if (executors[msg.sender] == 0) revert Errors.NotAllowed();
        CampaignParameters memory params = defaultParams;
        if (params.campaignData.length == 0) revert Errors.InvalidParams();
        params.startTimestamp = uint32(block.timestamp - startTimestampOffset);
        params.amount = amount;
        DistributionCreator _distributionCreator = merklDistributionCreator();
        _handleAllowance(params.rewardToken, address(_distributionCreator), amount);
        _distributionCreator.createCampaign(params);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the default campaign parameters for future campaigns
    /// @dev Parameters include campaign type, duration, distribution rules, and target pool/token.
    /// These can be configured using the Merkl campaign creation frontend.
    /// @param params The campaign parameters to use as default
    function setDefaultParameters(CampaignParameters memory params) external onlyOwner {
        defaultParams = params;
        emit DefaultParametersSet(params);
    }

    /// @notice Recovers tokens accidentally sent to this contract
    /// @dev This contract should not hold funds between transactions, so this is for emergency recovery
    /// @param token Address of the token to recover
    /// @param to Recipient address for the recovered tokens
    /// @param amount Amount of tokens to recover
    function recoverToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Updates the DistributionCreator contract address
    /// @dev Set to address(0) to use the default Merkl deployment address
    /// @param _distributionCreator The new DistributionCreator contract address
    function setDistributionCreator(address _distributionCreator) external onlyOwner {
        DistributionCreator(_distributionCreator).acceptConditions();
        distributionCreator = _distributionCreator;
        emit DistributionCreatorSet(_distributionCreator);
    }

    /// @notice Sets the offset subtracted from block.timestamp for campaign start time
    /// @dev Use this to create retroactive campaigns that start in the past
    /// @param _startTimestampOffset The offset in seconds to subtract from block.timestamp
    function setStartTimestampOffset(uint96 _startTimestampOffset) external onlyOwner {
        startTimestampOffset = _startTimestampOffset;
        emit StartTimestampOffsetSet(_startTimestampOffset);
    }

    /// @notice Adds or removes an executor from the whitelist
    /// @dev Executors are addresses authorized to call `notifyReward` and create campaigns
    /// @param executor Address to update executor status for
    /// @param status Non-zero value to authorize, zero to revoke authorization
    function setExecutor(address executor, uint256 status) external onlyOwner {
        executors[executor] = status;
        emit ExecutorSet(executor, status);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensures sufficient allowance for the DistributionCreator to spend tokens
    /// @dev Grants max approval if current allowance is insufficient. This is safe because
    /// this contract should not hold funds and Merkl contracts are trusted.
    /// @param token The token to approve
    /// @param _distributionCreator The spender address (DistributionCreator)
    /// @param amount The minimum required allowance
    function _handleAllowance(address token, address _distributionCreator, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), _distributionCreator);
        if (currentAllowance < amount) IERC20(token).safeIncreaseAllowance(_distributionCreator, type(uint256).max - currentAllowance);
    }
}
