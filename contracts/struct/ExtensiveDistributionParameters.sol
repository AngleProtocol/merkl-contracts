// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "./DistributionParameters.sol";

struct UniswapTokenData {
    address add;
    uint8 decimals;
    string symbol;
    uint256 poolBalance;
}

struct ExtensiveDistributionParameters {
    DistributionParameters base;
    // Uniswap pool data
    uint24 poolFee;
    UniswapTokenData token0;
    UniswapTokenData token1;
    // rewardToken data
    string rewardTokenSymbol;
    uint8 rewardTokenDecimals;
}
