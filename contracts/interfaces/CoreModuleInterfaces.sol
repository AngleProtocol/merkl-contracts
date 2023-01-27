// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

/// @title IAngleMiddlemanGauge
/// @author Angle Core Team
/// @notice Interface for the `AngleMiddleman` contract
interface IAngleMiddlemanGauge {
    function notifyReward(address gauge, uint256 amount) external;
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IGaugeController {
    //solhint-disable-next-line
    function gauge_types(address addr) external view returns (int128);

    //solhint-disable-next-line
    function gauge_relative_weight_write(address addr, uint256 timestamp) external returns (uint256);

    //solhint-disable-next-line
    function gauge_relative_weight(address addr, uint256 timestamp) external view returns (uint256);
}

interface ILiquidityGauge {
    // solhint-disable-next-line
    function deposit_reward_token(address _rewardToken, uint256 _amount) external;
}
