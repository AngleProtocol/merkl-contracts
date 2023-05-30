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

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/external/uniswap/IUniswapV3Pool.sol";
import "./utils/UUPSHelper.sol";
import "./struct/DistributionParameters.sol";
import "./struct/ExtensiveDistributionParameters.sol";
import "./struct/RewardTokenAmounts.sol";

/// @title DistributionCreator
/// @author Angle Labs, Inc.
/// @notice Manages the distribution of rewards across different pools with concentrated liquidity (like on Uniswap V3)
/// @dev This contract is mostly a helper for APIs built on top of Merkl
/// @dev People depositing rewards must have signed a `message` with the conditions for using the
/// product
//solhint-disable
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

    /// @notice Value (in base 10**9) of the fees taken when creating a distribution for a pool which do not
    /// have a whitelisted token in it
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

    // =================================== EVENTS ==================================

    event DistributorUpdated(address indexed _distributor);
    event FeeRebateUpdated(address indexed user, uint256 userFeeRebate);
    event FeeRecipientUpdated(address indexed _feeRecipient);
    event FeesSet(uint256 _fees);
    event MessageUpdated(bytes32 _messageHash);
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

    /// @notice Checks whether an address has signed the message or not
    modifier hasSigned() {
        if (userSignatureWhitelist[msg.sender] == 0 && userSignatures[msg.sender] != messageHash) revert NotSigned();
        _;
    }

    // ================================ CONSTRUCTOR ================================

    function initialize(ICore _core, address _distributor, uint256 _fees) external initializer {
        if (address(_core) == address(0) || _distributor == address(0)) revert ZeroAddress();
        if (_fees > BASE_9) revert InvalidParam();
        distributor = _distributor;
        core = _core;
        fees = _fees;
    }

    constructor() initializer {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGuardianUpgrader(core) {}

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

    /// @notice Checks whether the `msg.sender`'s `signature` is compatible with the message
    /// to sign and stores the signature
    /// @dev If you signed the message once, and the message has not been modified, then you do not
    /// need to sign again
    function sign(bytes calldata signature) external {
        _sign(signature);
    }

    /// @notice Combines signing the message and creating a distribution
    function signAndCreateDistribution(
        DistributionParameters memory distribution,
        bytes calldata signature
    ) external returns (uint256 distributionAmount) {
        _sign(signature);
        return _createDistribution(distribution);
    }

    /// @notice Internal version of `createDistribution`
    function _createDistribution(
        DistributionParameters memory distribution
    ) internal nonReentrant returns (uint256 distributionAmount) {
        uint32 epochStart = _getRoundedEpoch(distribution.epochStart);
        uint256 minDistributionAmount = rewardTokenMinAmounts[distribution.rewardToken];
        distribution.epochStart = epochStart;
        // Reward are not accepted in the following conditions:
        if (
            // if epoch parameters lead to a past distribution
            epochStart + EPOCH_DURATION < block.timestamp ||
            // if the amount of epochs for which this distribution should last is zero
            distribution.numEpoch == 0 ||
            // if the distribution parameters are not correctly specified
            distribution.propFees + distribution.propToken0 + distribution.propToken1 != 1e4 ||
            // if boosted addresses get less than non-boosted addresses in case of
            (distribution.boostingAddress != address(0) && distribution.boostedReward < 1e4) ||
            // if the type of the position wrappers is not well specified
            distribution.positionWrappers.length != distribution.wrapperTypes.length ||
            // if the reward token is not whitelisted as an incentive token
            minDistributionAmount == 0 ||
            // if the amount distributed is too small with respect to what is allowed
            distribution.amount / distribution.numEpoch < minDistributionAmount
        ) revert InvalidReward();
        distributionAmount = distribution.amount;
        // Computing fees: these are waived for whitelisted addresses and if there is a whitelisted token in a pool
        uint256 userFeeRebate = feeRebate[msg.sender];
        if (
            userFeeRebate < BASE_9 &&
            isWhitelistedToken[IUniswapV3Pool(distribution.uniV3Pool).token0()] == 0 &&
            isWhitelistedToken[IUniswapV3Pool(distribution.uniV3Pool).token1()] == 0
        ) {
            uint256 _fees = (fees * (BASE_9 - userFeeRebate)) / BASE_9;
            uint256 distributionAmountMinusFees = (distributionAmount * (BASE_9 - _fees)) / BASE_9;
            address _feeRecipient = feeRecipient;
            _feeRecipient = _feeRecipient == address(0) ? address(this) : _feeRecipient;
            IERC20(distribution.rewardToken).safeTransferFrom(
                msg.sender,
                _feeRecipient,
                distributionAmount - distributionAmountMinusFees
            );
            distributionAmount = distributionAmountMinusFees;
            distribution.amount = distributionAmount;
        }

        IERC20(distribution.rewardToken).safeTransferFrom(msg.sender, distributor, distributionAmount);
        uint256 senderNonce = nonces[msg.sender];
        nonces[msg.sender] = senderNonce + 1;
        distribution.rewardId = bytes32(keccak256(abi.encodePacked(msg.sender, senderNonce)));
        distributionList.push(distribution);
        emit NewDistribution(distribution, msg.sender);
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

    /// @notice Returns the list of all distributions ever made or to be done in the future
    function getAllDistributions() external view returns (DistributionParameters[] memory) {
        return distributionList;
    }

    /// @notice Returns the list of all currently active distributions on pools of supported AMMs (like Uniswap V3)
    function getActiveDistributions() external view returns (ExtensiveDistributionParameters[] memory) {
        uint32 roundedEpoch = _getRoundedEpoch(uint32(block.timestamp));
        return _getPoolDistributionsBetweenEpochs(address(0), roundedEpoch, roundedEpoch + EPOCH_DURATION);
    }

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
        RewardTokenAmounts[] memory validRewardTokensShort = new RewardTokenAmounts[](length);
        for (uint32 i; i < length; ) {
            validRewardTokensShort[i] = validRewardTokens[i];
            unchecked {
                ++i;
            }
        }
        return validRewardTokensShort;
    }

    /// @notice Returns the list of all the distributions that were or that are going to be live at
    /// a specific epoch
    function getDistributionsForEpoch(uint32 epoch) external view returns (ExtensiveDistributionParameters[] memory) {
        uint32 roundedEpoch = _getRoundedEpoch(epoch);
        return _getPoolDistributionsBetweenEpochs(address(0), roundedEpoch, roundedEpoch + EPOCH_DURATION);
    }

    /// @notice Gets the distributions that were or will be live at some point between `epochStart` (included) and `epochEnd` (excluded)
    /// @dev If a distribution starts during `epochEnd`, it is not be returned by this function
    /// @dev Conversely, if a distribution starts after `epochStart` and ends before `epochEnd`, it is returned by this function
    function getDistributionsBetweenEpochs(
        uint32 epochStart,
        uint32 epochEnd
    ) external view returns (ExtensiveDistributionParameters[] memory) {
        return _getPoolDistributionsBetweenEpochs(address(0), _getRoundedEpoch(epochStart), _getRoundedEpoch(epochEnd));
    }

    /// @notice Returns the list of all distributions that were or will be live after `epochStart` (included)
    function getDistributionsAfterEpoch(
        uint32 epochStart
    ) external view returns (ExtensiveDistributionParameters[] memory) {
        return _getPoolDistributionsBetweenEpochs(address(0), _getRoundedEpoch(epochStart), type(uint32).max);
    }

    /// @notice Returns the list of all currently active distributions for a specific UniswapV3 pool
    function getActivePoolDistributions(
        address uniV3Pool
    ) external view returns (ExtensiveDistributionParameters[] memory) {
        uint32 roundedEpoch = _getRoundedEpoch(uint32(block.timestamp));
        return _getPoolDistributionsBetweenEpochs(uniV3Pool, roundedEpoch, roundedEpoch + EPOCH_DURATION);
    }

    /// @notice Returns the list of all the distributions that were or that are going to be live at a
    /// specific epoch and for a specific pool
    function getPoolDistributionsForEpoch(
        address uniV3Pool,
        uint32 epoch
    ) external view returns (ExtensiveDistributionParameters[] memory) {
        uint32 roundedEpoch = _getRoundedEpoch(epoch);
        return _getPoolDistributionsBetweenEpochs(uniV3Pool, roundedEpoch, roundedEpoch + EPOCH_DURATION);
    }

    /// @notice Returns the list of all distributions that were or will be live between `epochStart` (included) and `epochEnd` (excluded)
    /// for a specific pool
    function getPoolDistributionsBetweenEpochs(
        address uniV3Pool,
        uint32 epochStart,
        uint32 epochEnd
    ) external view returns (ExtensiveDistributionParameters[] memory) {
        return _getPoolDistributionsBetweenEpochs(uniV3Pool, _getRoundedEpoch(epochStart), _getRoundedEpoch(epochEnd));
    }

    /// @notice Returns the list of all distributions that were or will be live after `epochStart` (included)
    /// for a specific pool
    function getPoolDistributionsAfterEpoch(
        address uniV3Pool,
        uint32 epochStart
    ) external view returns (ExtensiveDistributionParameters[] memory) {
        return _getPoolDistributionsBetweenEpochs(uniV3Pool, _getRoundedEpoch(epochStart), type(uint32).max);
    }

    // ============================ GOVERNANCE FUNCTIONS ===========================

    /// @notice Sets a new `distributor` to which rewards should be distributed
    function setNewDistributor(address _distributor) external onlyGovernorOrGuardian {
        if (_distributor == address(0)) revert InvalidParam();
        distributor = _distributor;
        emit DistributorUpdated(_distributor);
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

    /// @notice Sets the minimum amounts per distribution epoch for different reward tokens
    function setRewardTokenMinAmounts(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external onlyGovernorOrGuardian {
        uint256 tokensLength = tokens.length;
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
    function setFeeRecipient(address _feeRecipient) external onlyGovernorOrGuardian {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /// @notice Sets the message that needs to be signed by users before posting rewards
    function setMessage(string memory _message) external onlyGovernorOrGuardian {
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

    /// @notice Checks whether `distribution` was live between `roundedEpochStart` and `roundedEpochEnd`
    function _isDistributionLiveBetweenEpochs(
        DistributionParameters storage distribution,
        uint32 roundedEpochStart,
        uint32 roundedEpochEnd
    ) internal view returns (bool) {
        uint256 distributionEpochStart = distribution.epochStart;
        return (distributionEpochStart + distribution.numEpoch * EPOCH_DURATION > roundedEpochStart &&
            distributionEpochStart < roundedEpochEnd);
    }

    /// @notice Fetches data for `token` on the Uniswap `pool`
    function _getUniswapTokenData(
        IERC20Metadata token,
        address pool
    ) internal view returns (UniswapTokenData memory data) {
        data.add = address(token);
        data.decimals = token.decimals();
        data.symbol = token.symbol();
        data.poolBalance = token.balanceOf(pool);
    }

    /// @notice Fetches extra data about the parameters in a distribution
    function _getExtensiveDistributionParameters(
        DistributionParameters memory distribution
    ) internal view returns (ExtensiveDistributionParameters memory extensiveParams) {
        extensiveParams.base = distribution;
        try IUniswapV3Pool(distribution.uniV3Pool).fee() returns (uint24 fee) {
            extensiveParams.poolFee = fee;
        } catch {
            extensiveParams.poolFee = 0;
        }
        extensiveParams.token0 = _getUniswapTokenData(
            IERC20Metadata(IUniswapV3Pool(distribution.uniV3Pool).token0()),
            distribution.uniV3Pool
        );
        extensiveParams.token1 = _getUniswapTokenData(
            IERC20Metadata(IUniswapV3Pool(distribution.uniV3Pool).token1()),
            distribution.uniV3Pool
        );
        extensiveParams.rewardTokenSymbol = IERC20Metadata(distribution.rewardToken).symbol();
        extensiveParams.rewardTokenDecimals = IERC20Metadata(distribution.rewardToken).decimals();
    }

    /// @notice Gets the list of all the distributions for `uniV3Pool` that have been active between `epochStart` and `epochEnd` (excluded)
    /// @dev If the `uniV3Pool` parameter is equal to 0, then this function will return the distributions for all pools
    function _getPoolDistributionsBetweenEpochs(
        address uniV3Pool,
        uint32 epochStart,
        uint32 epochEnd
    ) internal view returns (ExtensiveDistributionParameters[] memory) {
        uint256 length;
        uint256 distributionListLength = distributionList.length;
        DistributionParameters[] memory longActiveRewards = new DistributionParameters[](distributionListLength);
        for (uint32 i; i < distributionListLength; ) {
            DistributionParameters storage distribution = distributionList[i];
            if (
                _isDistributionLiveBetweenEpochs(distribution, epochStart, epochEnd) &&
                (uniV3Pool == address(0) || distribution.uniV3Pool == uniV3Pool)
            ) {
                longActiveRewards[length] = distribution;
                length += 1;
            }
            unchecked {
                ++i;
            }
        }

        ExtensiveDistributionParameters[] memory activeRewards = new ExtensiveDistributionParameters[](length);
        for (uint32 i; i < length; ) {
            activeRewards[i] = _getExtensiveDistributionParameters(longActiveRewards[i]);
            unchecked {
                ++i;
            }
        }
        return activeRewards;
    }
}
