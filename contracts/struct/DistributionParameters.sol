// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

struct DistributionParameters {
    // ID of the reward (populated once created)
    bytes32 rewardId;
    // Address of the UniswapV3 pool that needs to be incentivized
    address uniV3Pool;
    // Address of the reward token for the incentives
    address rewardToken;
    // Amount of `rewardToken` to distribute across all the epochs
    // Amount distributed per epoch is `amount/numEpoch`
    uint256 amount;
    // List of all position wrappers to consider or not for this contract. Some wrappers like Gamma or Arrakis
    // are automatically detected and so there is no need to specify them here. Check out the docs to find out
    // which need to be specified and which are not automatically detected.
    address[] positionWrappers;
    // Type (Arrakis, Gamma, Blacklist, ...) encoded as a `uint32` for each wrapper in the list above. Mapping between
    // wrapper types and their corresponding `uint32` value can be found in Angle Docs
    uint32[] wrapperTypes;
    // In the incentivization formula, how much of the fees should go to holders of token0
    // in base 10**4
    uint32 propToken0;
    // Proportion for holding token1 (in base 10**4)
    uint32 propToken1;
    // Proportion for providing a useful liquidity (in base 10**4) that generates fees
    uint32 propFees;
    // Timestamp at which the incentivization should start
    uint32 epochStart;
    // Amount of epochs for which incentivization should last
    uint32 numEpoch;
    // Whether out of range liquidity should still be incentivized or not
    // This should be equal to 1 if out of range liquidity should still be incentivized
    // and 0 otherwise
    uint32 isOutOfRangeIncentivized;
    // How much more addresses with a maximum boost can get with respect to addresses
    // which do not have a boost (in base 4). In the case of Curve where addresses get 2.5x more
    // this would be 25000
    uint32 boostedReward;
    // Address of the token which dictates who gets boosted rewards or not. This is optional
    // and if the zero address is given no boost will be taken into account
    address boostingAddress;
    // Additional data passed when distributing rewards. This parameter may be used in case
    // the reward distribution script needs to look into other parameters beyond the ones above.
    bytes additionalData;
}
