// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/external/uniswap/IUniswapV3Pool.sol";
import "../interfaces/ICoreBorrow.sol";

/* TODO for the script
- check whether the uniV3 pool is actually one or not
- automatically ERC20 token addresses which own the position
- what happens if rewards sent to a pool with no fees accruing in the week at all
*/

struct RewardDistribution {
    // Address of the UniswapV3 pool that needs to be incentivized
    address uniV3Pool;
    // Address of the reward token for the incentives
    address token;
    // List of all UniV3 position wrappers to consider for this contract
    // (this can include addresses of Arrakis or Gamma smart contracts for instance)
    address[] positionWrappers;
    // Amount of `token` to distribute
    uint256 amount;
    // In the incentivization formula, how much of the fees should go to holders of token1
    // in base 10**4
    uint32 propToken1;
    // Proportion for holding token2 (in base 10**4)
    uint32 propToken2;
    // Proportion for providing a useful liquidity (in base 10**4) that generates fees
    uint32 propFees;
    // Timestamp at which the incentivization should start
    uint32 epochStart;
    // Amount of epochs for which incentivization should last
    uint32 numEpoch;
    // Whether out of range liquidity should still be incentivized or not
    // This should be equal to 1 if out of range liquidity should still be incentivized
    // and 0 otherwise
    uint32 outOfRangeIncentivized;
    // How much more addresses with a maximum boost can get with respect to addresses
    // which do not have a boost (in base 4). In the case of Curve where addresses get 2.5x more
    // this would be 25000
    uint32 boostedReward;
    // Address of the token which dictates who gets boosted rewards or not. This is optional
    // and if the zero address is given no boost will be taken into account
    address boostingAddress;
}

/// @title MerkleRewardManager
/// @author Angle Labs, Inc.
/// @notice Manages the distribution of rewards across different UniswapV3 pools
/// @dev This contract is mostly a helper for APIs getting built on top and helping in Angle
/// UniswapV3 incentivization scheme
abstract contract MerkleRewardManager is Initializable {
    using SafeERC20 for IERC20;

    // ============================ CONSTANT / VARIABLES ===========================
    /// @notice Epoch duration
    uint32 public constant EPOCH_DURATION = 24 * 3600 * 7;

    /// @notice `CoreBorrow` contract handling access control
    ICoreBorrow public coreBorrow;
    /// @notice User contract for distributing rewards
    address public merkleRootDistributor;
    /// @notice List of all rewards ever distributed or to be distributed in the contract
    RewardDistribution[] public rewardList;
    /// @notice Value (in base 10**9) of the fees taken when adding rewards for a pool which does not
    /// have agEUR in it
    uint256 public fees;
    /// @notice Maps an address to the rebate
    mapping(address => uint256) public feeRebate;

    uint256[47] private __gap;

    // ============================== ERRORS / EVENTS ==============================

    event FeesSet(uint256 _fees);
    event MerkleRootDistributorUpdated(address indexed _merkleRootDistributor);
    event NewReward(RewardDistribution reward, address indexed sender);
    event FeeRebateUpdated(address indexed user, uint256 userFeeRebate);

    error InvalidReward();
    error InvalidParam();
    error NotGovernorOrGuardian();
    error ZeroAddress();

    // ================================== MODIFIER =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!coreBorrow.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    // ================================ CONSTRUCTOR ================================

    constructor() initializer {}

    function initialize(
        ICoreBorrow _coreBorrow,
        address _merkleRootDistributor,
        uint256 _fees
    ) public initializer {
        if (address(_coreBorrow) == address(0) || _merkleRootDistributor == address(0)) revert ZeroAddress();
        if (_fees > 10**9) revert InvalidParam();
        merkleRootDistributor = _merkleRootDistributor;
        coreBorrow = _coreBorrow;
        fees = _fees;
    }

    // ============================== DEPOSIT FUNCTION =============================

    /// @notice Deposits a reward `reward` to incentivize a given UniswapV3 pool for a specific period of time
    /// @return rewardAmount How many rewards are actually taken into consideration in the contract
    /// @dev It's important to make sure that the address specified as a UniV3 pool is effectively a pool
    /// otherwise they will not be handled by the distribution script and rewards may be lost
    /// @dev The `positionWrappers` specified in the `reward` struct need to be supported by the script
    /// @dev If the pool incentivized contains agEUR, then no fees are taken on the rewards
    function depositReward(RewardDistribution memory reward) external returns (uint256 rewardAmount) {
        return _depositReward(reward);
    }

    /// @notice Same as the function above but for multiple rewards at once
    /// @return List of all the reward amounts actually deposited for each `reward` in the `rewards` list
    function depositRewards(RewardDistribution[] memory rewards) external returns (uint256[] memory) {
        uint256[] memory rewardAmounts = new uint256[](rewards.length);
        for (uint256 i = 0; i < rewards.length; ) {
            rewardAmounts[i] = _depositReward(rewards[i]);
            unchecked {
                ++i;
            }
        }
        return rewardAmounts;
    }

    /// @notice Internal version of `depositReward`
    function _depositReward(RewardDistribution memory reward) internal returns (uint256 rewardAmount) {
        uint32 epochStart = _getRoundedEpoch(reward.epochStart);
        reward.epochStart = epochStart;
        // Reward will not be accepted in the following conditions:
        if (
            // if epoch parameters would lead to a past distribution
            epochStart + EPOCH_DURATION < block.timestamp ||
            // if the amount of epochs for which this incentive should last is zero
            reward.numEpoch == 0 ||
            // if the amount to use to incentivize is still 0
            reward.amount == 0 ||
            // if the reward parameters are not correctly specified
            reward.propFees + reward.propToken1 + reward.propToken2 != 10**4 ||
            // if boosted addresses get less than non-boosted addresses in case of
            (reward.boostingAddress != address(0) && reward.boostedReward < 10**4)
        ) revert InvalidReward();
        rewardAmount = reward.amount;
        address agEURAddress = _agEUR();
        // Computing fees: these are waive for whitelisted addresses and if there is agEUR in a pool
        uint256 userFeeRebate = feeRebate[msg.sender];
        if (
            userFeeRebate < 10**9 &&
            IUniswapV3Pool(reward.uniV3Pool).token0() != agEURAddress &&
            IUniswapV3Pool(reward.uniV3Pool).token1() != agEURAddress
        ) {
            uint256 _fees = (fees * (10**9 - userFeeRebate)) / 10**9;
            uint256 rewardAmountMinusFees = (rewardAmount * (10**9 - _fees)) / 10**9;
            IERC20(reward.token).safeTransferFrom(msg.sender, address(this), rewardAmount - rewardAmountMinusFees);
            rewardAmount = rewardAmountMinusFees;
            reward.amount = rewardAmount;
        }

        IERC20(reward.token).safeTransferFrom(msg.sender, merkleRootDistributor, rewardAmount);
        rewardList.push(reward);
        emit NewReward(reward, msg.sender);
    }

    // ================================= UI HELPERS ================================
    // These functions are not to be queried on-chain and hence are not optimized for gas consumption

    /// @notice Returns the list of all rewards ever distributed or to be distributed
    function getAllRewards() external view returns (RewardDistribution[] memory) {
        return rewardList;
    }

    /// @notice Returns the list of all currently active rewards on UniswapV3 pool
    function getActiveRewards() external view returns (RewardDistribution[] memory) {
        return _getRewardsForEpoch(_getRoundedEpoch(uint32(block.timestamp)));
    }

    /// @notice Returns the list of all the rewards that were or that are going to be live at
    /// a specific epoch
    function getRewardsForEpoch(uint32 epoch) external view returns (RewardDistribution[] memory) {
        return _getRewardsForEpoch(_getRoundedEpoch(epoch));
    }

    /// @notice Returns the list of all currently active rewards for a specific UniswapV3 pool
    function getActivePoolRewards(address uniV3Pool) external view returns (RewardDistribution[] memory) {
        return _getPoolRewardsForEpoch(uniV3Pool, _getRoundedEpoch(uint32(block.timestamp)));
    }

    /// @notice Returns the list of all the rewards that were or that are going to be live at a
    /// specific epoch and for a specific pool
    function getPoolRewardsForEpoch(address uniV3Pool, uint32 epoch)
        external
        view
        returns (RewardDistribution[] memory)
    {
        return _getPoolRewardsForEpoch(uniV3Pool, _getRoundedEpoch(epoch));
    }

    // ============================ GOVERNANCE FUNCTIONS ===========================

    /// @notice Sets a new `merkleRootDistributor` to which rewards should be distributed
    function setNewMerkleRootDistributor(address _merkleRootDistributor) external onlyGovernorOrGuardian {
        if (_merkleRootDistributor == address(0)) revert InvalidParam();
        merkleRootDistributor = _merkleRootDistributor;
        emit MerkleRootDistributorUpdated(_merkleRootDistributor);
    }

    /// @notice Sets the fees on deposit
    function setFees(uint256 _fees) external onlyGovernorOrGuardian {
        if (_fees >= 10**9) revert InvalidParam();
        fees = _fees;
        emit FeesSet(_fees);
    }

    /// @notice Sets fee rebates for a given user
    function setUserFeeRebate(address user, uint256 userFeeRebate) external onlyGovernorOrGuardian {
        feeRebate[user] = userFeeRebate;
        emit FeeRebateUpdated(user, userFeeRebate);
    }

    /// @notice Recovers fees accrued on the contract for a list of `tokens`
    function recoverFees(IERC20[] memory tokens, address to) external onlyGovernorOrGuardian {
        for (uint256 i = 0; i < tokens.length; ) {
            uint256 amount = tokens[i].balanceOf(address(this));
            tokens[i].safeTransfer(to, amount);
            unchecked {
                ++i;
            }
        }
    }

    // ============================== INTERNAL HELPERS =============================

    /// @notice Returns the agEUR address on the corresponding chain
    function _agEUR() internal view virtual returns (address);

    /// @notice Rounds an `epoch` timestamp to the start of the corresponding period
    function _getRoundedEpoch(uint32 epoch) internal pure returns (uint32) {
        return (epoch / EPOCH_DURATION) * EPOCH_DURATION;
    }

    /// @notice Checks whether `reward` was live at `roundedEpoch`
    function _isRewardLiveForEpoch(RewardDistribution storage reward, uint32 roundedEpoch)
        internal
        view
        returns (bool)
    {
        uint256 rewardEpochStart = reward.epochStart;
        return rewardEpochStart <= roundedEpoch && rewardEpochStart + reward.numEpoch * EPOCH_DURATION > roundedEpoch;
    }

    /// @notice Gets the list of all active rewards during the epoch which started at `epochStart`
    function _getRewardsForEpoch(uint32 epochStart) internal view returns (RewardDistribution[] memory) {
        uint256 length;
        RewardDistribution[] memory longActiveRewards = new RewardDistribution[](rewardList.length);
        for (uint32 i = 0; i < rewardList.length; ) {
            RewardDistribution storage reward = rewardList[i];
            if (_isRewardLiveForEpoch(reward, epochStart)) {
                longActiveRewards[length] = reward;
                length += 1;
            }
            unchecked {
                ++i;
            }
        }
        RewardDistribution[] memory activeRewards = new RewardDistribution[](length);
        for (uint32 i = 0; i < length; ) {
            activeRewards[i] = longActiveRewards[i];
            unchecked {
                ++i;
            }
        }
        return activeRewards;
    }

    /// @notice Gets the list of all active rewards for `uniV3Pool` during the epoch which started at `epochStart`
    function _getPoolRewardsForEpoch(address uniV3Pool, uint32 epochStart)
        internal
        view
        returns (RewardDistribution[] memory)
    {
        uint256 length;
        RewardDistribution[] memory longActiveRewards = new RewardDistribution[](rewardList.length);
        for (uint32 i = 0; i < rewardList.length; ) {
            RewardDistribution storage reward = rewardList[i];
            if (reward.uniV3Pool == uniV3Pool && _isRewardLiveForEpoch(reward, epochStart)) {
                longActiveRewards[length] = reward;
                length += 1;
            }
            unchecked {
                ++i;
            }
        }

        RewardDistribution[] memory activeRewards = new RewardDistribution[](length);
        for (uint32 i = 0; i < length; ) {
            activeRewards[i] = longActiveRewards[i];
            unchecked {
                ++i;
            }
        }
        return activeRewards;
    }
}
