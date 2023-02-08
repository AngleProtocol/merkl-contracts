// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

contract MockUniswapV3Pool {
    address public token0;
    address public token1;
    uint32 public constant EPOCH_DURATION = 3600;
    uint256 public fee;

    function setToken(address token, uint256 who) external {
        if (who == 0) token0 = token;
        else token1 = token;
    }

    function round(uint256 amount) external pure returns (uint256) {
        return (amount / EPOCH_DURATION) * EPOCH_DURATION;
    }
}
