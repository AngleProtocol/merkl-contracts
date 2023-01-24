// SPDX-License-Identifier: GPL-3.0

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

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/external/uniswap/IUniswapV3Pool.sol";
import "../utils/UUPSHelper.sol";
import "hardhat/console.sol";

struct RewardParameters {
    // Address of the UniswapV3 pool that needs to be incentivized
    address uniV3Pool;
    // Address of the reward token for the incentives
    address token;
    // Amount of `token` to distribute
    uint256 amount;
    // List of all UniV3 position wrappers to consider for this contract
    // (this can include addresses of Arrakis or Gamma smart contracts for instance)
    address[] positionWrappers;
    // Type (Arrakis, Gamma, ...) encoded as a `uint32` for each wrapper in the list above. Mapping between wrapper types and their
    // corresponding `uint32` value can be found in Angle Docs
    uint32[] wrapperTypes;
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
    // ID of the reward (it is only populated once created)
    bytes32 rewardId;
}

struct SigningData {
    // Last message that was signed by a user
    bytes26 lastSignedMessage;
    // Whether the user is whitelisted not to give any signature on the message
    uint48 whitelistStatus;
}

/// @title MerkleRewardManager
/// @author Angle Labs, Inc.
/// @notice Manages the distribution of rewards across different UniswapV3 pools
/// @dev This contract is mostly a helper for APIs getting built on top and helping in Angle
/// UniswapV3 incentivization scheme
/// @dev People depositing rewards should have signed a `message` with the conditions for using the
/// product
contract MerkleRewardManager is UUPSHelper, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // ============================ CONSTANT / VARIABLES ===========================
    /// @notice Epoch duration
    uint32 public constant EPOCH_DURATION = 3600;
    /// @notice Base for fee computation
    uint256 public constant BASE_9 = 1e9;

    /// @notice `CoreBorrow` contract handling access control
    ICoreBorrow public coreBorrow;
    /// @notice User contract for distributing rewards
    address public merkleRootDistributor;
    /// @notice Value (in base 10**9) of the fees taken when adding rewards for a pool which do not
    /// have a whitelisted token in it
    uint256 public fees;
    /// @notice Message that needs to be acknowledged by users depositing rewards
    string public message;
    /// @notice Hash of the message that needs to be signed
    bytes26 public messageHash;
    /// @notice List of all rewards ever distributed or to be distributed in the contract
    RewardParameters[] public rewardList;
    /// @notice Maps an address to its fee rebate
    mapping(address => uint256) public feeRebate;
    /// @notice Maps a token to whether it is whitelisted or not. No fees are to be paid for incentives given
    /// on pools with whitelisted tokens
    mapping(address => uint256) public isWhitelistedToken;
    /// @notice Maps an address to its nonce for depositing a reward
    mapping(address => uint256) public nonces;
    /// @notice Maps an address to its signing data
    mapping(address => SigningData) public userSigningData;

    uint256[40] private __gap;

    // ============================== ERRORS / EVENTS ==============================

    event FeesSet(uint256 _fees);
    event MerkleRootDistributorUpdated(address indexed _merkleRootDistributor);
    event MessageUpdated(bytes26 _messageHash);
    event NewReward(RewardParameters reward, address indexed sender);
    event FeeRebateUpdated(address indexed user, uint256 userFeeRebate);
    event TokenWhitelistToggled(address indexed token, uint256 toggleStatus);
    event UserSigned(bytes26 messageHash, address indexed user);
    event UserSigningWhitelistToggled(address indexed user, uint48 toggleStatus);

    // ================================== MODIFIER =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!coreBorrow.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @notice Checks whether an address has signed the message or not
    modifier hasSigned() {
        SigningData storage userData = userSigningData[msg.sender];
        if (userData.whitelistStatus == 0 && userData.lastSignedMessage != messageHash) revert NotSigned();
        _;
    }

    // ================================ CONSTRUCTOR ================================

    function initialize(
        ICoreBorrow _coreBorrow,
        address _merkleRootDistributor,
        uint256 _fees
    ) external initializer {
        if (address(_coreBorrow) == address(0) || _merkleRootDistributor == address(0)) revert ZeroAddress();
        if (_fees > BASE_9) revert InvalidParam();
        merkleRootDistributor = _merkleRootDistributor;
        coreBorrow = _coreBorrow;
        fees = _fees;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGuardianUpgrader(coreBorrow) {}

    // ============================== DEPOSIT FUNCTION =============================

    /// @notice Deposits a reward `reward` to incentivize a given UniswapV3 pool for a specific period of time
    /// @return rewardAmount How many rewards are actually taken into consideration in the contract
    /// @dev It's important to make sure that the address specified as a UniV3 pool is effectively a pool
    /// otherwise they will not be handled by the distribution script and rewards may be lost
    /// @dev The `positionWrappers` specified in the `reward` struct need to be supported by the script
    /// @dev If the pool incentivized contains agEUR, then no fees are taken on the rewards
    /// @dev This function will revert if the user has not signed the message `messageHash` once through one of
    /// the functions enabling to sign
    function depositReward(RewardParameters memory reward) external hasSigned returns (uint256 rewardAmount) {
        return _depositReward(reward);
    }

    /// @notice Same as the function above but for multiple rewards at once
    /// @return List of all the reward amounts actually deposited for each `reward` in the `rewards` list
    function depositRewards(RewardParameters[] memory rewards) external hasSigned returns (uint256[] memory) {
        uint256 rewardsLength = rewards.length;
        uint256[] memory rewardAmounts = new uint256[](rewardsLength);
        for (uint256 i; i < rewardsLength; ) {
            rewardAmounts[i] = _depositReward(rewards[i]);
            unchecked {
                ++i;
            }
        }
        return rewardAmounts;
    }

    /// @notice Checks whether the `msg.sender`'s `signature` is compatible with the message
    /// to sign and stores the fact that signing was done
    /// @dev If you signed the message once, and the message has not been modified, then you do not
    /// need to sign again
    function sign(bytes calldata signature) external {
        _sign(signature);
    }

    /// @notice Combines signing the message and depositing a reward
    function signAndDepositReward(RewardParameters memory reward, bytes calldata signature)
        external
        returns (uint256 rewardAmount)
    {
        _sign(signature);
        return _depositReward(reward);
    }

    /// @notice Internal version of `depositReward`
    function _depositReward(RewardParameters memory reward) internal nonReentrant returns (uint256 rewardAmount) {
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
            reward.propFees + reward.propToken1 + reward.propToken2 != 1e4 ||
            // if boosted addresses get less than non-boosted addresses in case of
            (reward.boostingAddress != address(0) && reward.boostedReward < 1e4) ||
            // if the type of the position wrappers is not well specified
            reward.positionWrappers.length != reward.wrapperTypes.length
        ) revert InvalidReward();
        rewardAmount = reward.amount;
        // Computing fees: these are waived for whitelisted addresses and if there is a whitelisted token in a pool
        uint256 userFeeRebate = feeRebate[msg.sender];
        if (
            userFeeRebate < BASE_9 &&
            isWhitelistedToken[IUniswapV3Pool(reward.uniV3Pool).token0()] == 0 &&
            isWhitelistedToken[IUniswapV3Pool(reward.uniV3Pool).token1()] == 0
        ) {
            uint256 _fees = (fees * (BASE_9 - userFeeRebate)) / BASE_9;
            uint256 rewardAmountMinusFees = (rewardAmount * (BASE_9 - _fees)) / BASE_9;
            IERC20(reward.token).safeTransferFrom(msg.sender, address(this), rewardAmount - rewardAmountMinusFees);
            rewardAmount = rewardAmountMinusFees;
            reward.amount = rewardAmount;
        }

        IERC20(reward.token).safeTransferFrom(msg.sender, merkleRootDistributor, rewardAmount);
        uint256 senderNonce = nonces[msg.sender];
        nonces[msg.sender] = senderNonce + 1;
        reward.rewardId = bytes32(keccak256(abi.encodePacked(msg.sender, senderNonce)));
        rewardList.push(reward);
        emit NewReward(reward, msg.sender);
    }

    /// @notice Internal version of the `sign` function
    function _sign(bytes calldata signature) internal {
        bytes26 _messageHash = messageHash;
        console.logBytes26(_messageHash);
        console.logBytes32(_messageHash);
        console.log(ECDSA.recover(_messageHash, signature));
        console.log(msg.sender);
        // if (ECDSA.recover(_messageHash, signature) != msg.sender) revert InvalidSignature();
        SigningData storage userData = userSigningData[msg.sender];
        userData.lastSignedMessage = _messageHash;
        emit UserSigned(_messageHash, msg.sender);
    }

    // ================================= UI HELPERS ================================
    // These functions are not to be queried on-chain and hence are not optimized for gas consumption

    /// @notice Returns the list of all rewards ever distributed or to be distributed
    function getAllRewards() external view returns (RewardParameters[] memory) {
        return rewardList;
    }

    /// @notice Returns the list of all currently active rewards on UniswapV3 pool
    function getActiveRewards() external view returns (RewardParameters[] memory) {
        return _getRewardsForEpoch(_getRoundedEpoch(uint32(block.timestamp)));
    }

    /// @notice Returns the list of all the rewards that were or that are going to be live at
    /// a specific epoch
    function getRewardsForEpoch(uint32 epoch) external view returns (RewardParameters[] memory) {
        return _getRewardsForEpoch(_getRoundedEpoch(epoch));
    }

    /// @notice Gets the rewards that were or will be live at some point between `epochStart` (included) and `epochEnd` (excluded)
    /// @dev If a reward starts during `epochEnd`, it will not be returned by this function
    /// @dev Conversely, if a reward starts after `epochStart` and ends before `epochEnd`, it will be returned by this function
    function getRewardsBetweenEpochs(uint32 epochStart, uint32 epochEnd)
        external
        view
        returns (RewardParameters[] memory)
    {
        return _getRewardsBetweenEpochs(_getRoundedEpoch(epochStart), _getRoundedEpoch(epochEnd));
    }

    /// @notice Returns the list of all rewards that were or will be live after `epochStart` (included)
    function getRewardsAfterEpoch(uint32 epochStart) external view returns (RewardParameters[] memory) {
        return _getRewardsBetweenEpochs(_getRoundedEpoch(epochStart), type(uint32).max);
    }

    /// @notice Returns the list of all currently active rewards for a specific UniswapV3 pool
    function getActivePoolRewards(address uniV3Pool) external view returns (RewardParameters[] memory) {
        return _getPoolRewardsForEpoch(uniV3Pool, _getRoundedEpoch(uint32(block.timestamp)));
    }

    /// @notice Returns the list of all the rewards that were or that are going to be live at a
    /// specific epoch and for a specific pool
    function getPoolRewardsForEpoch(address uniV3Pool, uint32 epoch) external view returns (RewardParameters[] memory) {
        return _getPoolRewardsForEpoch(uniV3Pool, _getRoundedEpoch(epoch));
    }

    /// @notice Returns the list of all rewards that were or will be live between `epochStart` (included) and `epochEnd` (excluded)
    /// for a specific pool
    function getPoolRewardsBetweenEpochs(
        address uniV3Pool,
        uint32 epochStart,
        uint32 epochEnd
    ) external view returns (RewardParameters[] memory) {
        return _getPoolRewardsBetweenEpochs(uniV3Pool, _getRoundedEpoch(epochStart), _getRoundedEpoch(epochEnd));
    }

    /// @notice Returns the list of all rewards that were or will be live after `epochStart` (included)
    /// for a specific pool
    function getPoolRewardsAfterEpoch(address uniV3Pool, uint32 epochStart)
        external
        view
        returns (RewardParameters[] memory)
    {
        return _getPoolRewardsBetweenEpochs(uniV3Pool, _getRoundedEpoch(epochStart), type(uint32).max);
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
        if (_fees >= BASE_9) revert InvalidParam();
        fees = _fees;
        emit FeesSet(_fees);
    }

    /// @notice Sets fee rebates for a given user
    function setUserFeeRebate(address user, uint256 userFeeRebate) external onlyGovernorOrGuardian {
        feeRebate[user] = userFeeRebate;
        emit FeeRebateUpdated(user, userFeeRebate);
    }

    /// @notice Toggles the fee whitelist for `token`
    function toggleTokenWhitelist(address token) external onlyGovernorOrGuardian {
        uint256 toggleStatus = 1 - isWhitelistedToken[token];
        isWhitelistedToken[token] = toggleStatus;
        emit TokenWhitelistToggled(token, toggleStatus);
    }

    /// @notice Recovers fees accrued on the contract for a list of `tokens`
    function recoverFees(IERC20[] calldata tokens, address to) external onlyGovernorOrGuardian {
        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength; ) {
            tokens[i].safeTransfer(to, tokens[i].balanceOf(address(this)));
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets the message that needs to be signed by users before posting rewards
    function setMessage(string memory _message) external onlyGovernorOrGuardian {
        message = _message;
        bytes26 _messageHash = bytes26(ECDSA.toEthSignedMessageHash(bytes(_message)));
        messageHash = _messageHash;
        emit MessageUpdated(_messageHash);
    }

    /// @notice Toggles the whitelist status for `user` when it comes to signing messages before depositing
    /// rewards
    function toggleSigningWhitelist(address user) external onlyGovernorOrGuardian {
        SigningData storage userData = userSigningData[user];
        uint48 whitelistStatus = 1 - userData.whitelistStatus;
        userData.whitelistStatus = whitelistStatus;
        emit UserSigningWhitelistToggled(user, whitelistStatus);
    }

    // ============================== INTERNAL HELPERS =============================

    /// @notice Rounds an `epoch` timestamp to the start of the corresponding period
    function _getRoundedEpoch(uint32 epoch) internal pure returns (uint32) {
        return (epoch / EPOCH_DURATION) * EPOCH_DURATION;
    }

    /// @notice Checks whether `reward` was live at `roundedEpoch`
    function _isRewardLiveForEpoch(RewardParameters storage reward, uint32 roundedEpoch) internal view returns (bool) {
        uint256 rewardEpochStart = reward.epochStart;
        return rewardEpochStart <= roundedEpoch && rewardEpochStart + reward.numEpoch * EPOCH_DURATION > roundedEpoch;
    }

    /// @notice Checks whether `reward` was live between `roundedEpochStart` and `roundedEpochEnd`
    function _isRewardLiveBetweenEpochs(
        RewardParameters storage reward,
        uint32 roundedEpochStart,
        uint32 roundedEpochEnd
    ) internal view returns (bool) {
        uint256 rewardEpochStart = reward.epochStart;
        return (rewardEpochStart + reward.numEpoch * EPOCH_DURATION > roundedEpochStart &&
            rewardEpochStart < roundedEpochEnd);
    }

    /// @notice Gets the list of all active rewards during the epoch which started at `epochStart`
    function _getRewardsForEpoch(uint32 epochStart) internal view returns (RewardParameters[] memory) {
        uint256 length;
        uint256 rewardListLength = rewardList.length;
        RewardParameters[] memory longActiveRewards = new RewardParameters[](rewardListLength);
        for (uint32 i; i < rewardListLength; ) {
            RewardParameters storage reward = rewardList[i];
            if (_isRewardLiveForEpoch(reward, epochStart)) {
                longActiveRewards[length] = reward;
                length += 1;
            }
            unchecked {
                ++i;
            }
        }
        RewardParameters[] memory activeRewards = new RewardParameters[](length);
        for (uint32 i; i < length; ) {
            activeRewards[i] = longActiveRewards[i];
            unchecked {
                ++i;
            }
        }
        return activeRewards;
    }

    /// @notice Gets the list of rewards that have been active at some point between `epochStart` and `epochEnd` (excluded)
    function _getRewardsBetweenEpochs(uint32 epochStart, uint32 epochEnd)
        internal
        view
        returns (RewardParameters[] memory)
    {
        uint256 length;
        uint256 rewardListLength = rewardList.length;
        RewardParameters[] memory longActiveRewards = new RewardParameters[](rewardListLength);
        for (uint32 i; i < rewardListLength; ) {
            RewardParameters storage reward = rewardList[i];
            if (_isRewardLiveBetweenEpochs(reward, epochStart, epochEnd)) {
                longActiveRewards[length] = reward;
                length += 1;
            }
            unchecked {
                ++i;
            }
        }
        RewardParameters[] memory activeRewards = new RewardParameters[](length);
        for (uint32 i; i < length; ) {
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
        returns (RewardParameters[] memory)
    {
        uint256 length;
        uint256 rewardListLength = rewardList.length;
        RewardParameters[] memory longActiveRewards = new RewardParameters[](rewardListLength);
        for (uint32 i; i < rewardListLength; ) {
            RewardParameters storage reward = rewardList[i];
            if (reward.uniV3Pool == uniV3Pool && _isRewardLiveForEpoch(reward, epochStart)) {
                longActiveRewards[length] = reward;
                length += 1;
            }
            unchecked {
                ++i;
            }
        }

        RewardParameters[] memory activeRewards = new RewardParameters[](length);
        for (uint32 i; i < length; ) {
            activeRewards[i] = longActiveRewards[i];
            unchecked {
                ++i;
            }
        }
        return activeRewards;
    }

    /// @notice Gets the list of all the rewards for `uniV3Pool` that have been active between `epochStart` and `epochEnd` (excluded)
    function _getPoolRewardsBetweenEpochs(
        address uniV3Pool,
        uint32 epochStart,
        uint32 epochEnd
    ) internal view returns (RewardParameters[] memory) {
        uint256 length;
        uint256 rewardListLength = rewardList.length;
        RewardParameters[] memory longActiveRewards = new RewardParameters[](rewardListLength);
        for (uint32 i; i < rewardListLength; ) {
            RewardParameters storage reward = rewardList[i];
            if (reward.uniV3Pool == uniV3Pool && _isRewardLiveBetweenEpochs(reward, epochStart, epochEnd)) {
                longActiveRewards[length] = reward;
                length += 1;
            }
            unchecked {
                ++i;
            }
        }

        RewardParameters[] memory activeRewards = new RewardParameters[](length);
        for (uint32 i; i < length; ) {
            activeRewards[i] = longActiveRewards[i];
            unchecked {
                ++i;
            }
        }
        return activeRewards;
    }
}
