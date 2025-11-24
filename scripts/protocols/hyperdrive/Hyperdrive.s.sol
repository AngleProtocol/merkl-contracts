// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "../../utils/Base.s.sol";
import { MockToken } from "../../../contracts/mock/MockToken.sol";

// Base contract with shared utilities
contract MockTokenScript is BaseScript {}

// HyperdriveLP script
contract HyperdriveLP is MockTokenScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED MINT PARAMETERS
        address token = 0xD9b66D9a819B36ECEfC26B043eF3B422d5A6123a;
        _run(token);
    }

    function run(address token) external broadcast {
        _run(token);
    }

    function _run(address token) internal {
        address user = 0x9eB168Ab44B7c479431681558FdF34230c969DE9;
        IHyperdrive.PoolInfo memory poolInfo = IHyperdriveLP(token).getPoolInfo();
        uint256 lpBalance = IHyperdriveLP(token).balanceOf(0, user);
        console.log("Price LP %s is %s", token, poolInfo.lpSharePrice);
        console.log("LP balance %s is %s", user, lpBalance);
    }
}

interface IHyperdrive {
    /// Structs ///

    struct MarketState {
        /// @dev The pool's share reserves.
        uint128 shareReserves;
        /// @dev The pool's bond reserves.
        uint128 bondReserves;
        /// @dev The global exposure of the pool due to open longs
        uint128 longExposure;
        /// @dev The amount of longs that are still open.
        uint128 longsOutstanding;
        /// @dev The net amount of shares that have been added and removed from
        ///      the share reserves due to flat updates.
        int128 shareAdjustment;
        /// @dev The amount of shorts that are still open.
        uint128 shortsOutstanding;
        /// @dev The average maturity time of outstanding long positions.
        uint128 longAverageMaturityTime;
        /// @dev The average maturity time of outstanding short positions.
        uint128 shortAverageMaturityTime;
        /// @dev A flag indicating whether or not the pool has been initialized.
        bool isInitialized;
        /// @dev A flag indicating whether or not the pool is paused.
        bool isPaused;
        /// @dev The proceeds in base of the unredeemed matured positions.
        uint112 zombieBaseProceeds;
        /// @dev The shares reserved for unredeemed matured positions.
        uint128 zombieShareReserves;
    }

    struct Checkpoint {
        /// @dev The time-weighted average spot price of the checkpoint. This is
        ///      used to implement circuit-breakers that prevents liquidity from
        ///      being added when the pool's rate moves too quickly.
        uint128 weightedSpotPrice;
        /// @dev The last time the weighted spot price was updated.
        uint128 lastWeightedSpotPriceUpdateTime;
        /// @dev The vault share price during the first transaction in the
        ///      checkpoint. This is used to track the amount of interest
        ///      accrued by shorts as well as the vault share price at closing
        ///      of matured longs and shorts.
        uint128 vaultSharePrice;
    }

    struct WithdrawPool {
        /// @dev The amount of withdrawal shares that are ready to be redeemed.
        uint128 readyToWithdraw;
        /// @dev The proceeds recovered by the withdrawal pool.
        uint128 proceeds;
    }

    struct Fees {
        /// @dev The LP fee applied to the curve portion of a trade.
        uint256 curve;
        /// @dev The LP fee applied to the flat portion of a trade.
        uint256 flat;
        /// @dev The portion of the LP fee that goes to governance.
        uint256 governanceLP;
        /// @dev The portion of the zombie interest that goes to governance.
        uint256 governanceZombie;
    }

    struct PoolDeployConfig {
        /// @dev The address of the base token.
        IERC20 baseToken;
        /// @dev The address of the vault shares token.
        IERC20 vaultSharesToken;
        /// @dev The linker factory used by this Hyperdrive instance.
        address linkerFactory;
        /// @dev The hash of the ERC20 linker's code. This is used to derive the
        ///      create2 addresses of the ERC20 linkers used by this instance.
        bytes32 linkerCodeHash;
        /// @dev The minimum share reserves.
        uint256 minimumShareReserves;
        /// @dev The minimum amount of tokens that a position can be opened or
        ///      closed with.
        uint256 minimumTransactionAmount;
        /// @dev The maximum delta between the last checkpoint's weighted spot
        ///      APR and the current spot APR for an LP to add liquidity. This
        ///      protects LPs from sandwich attacks.
        uint256 circuitBreakerDelta;
        /// @dev The duration of a position prior to maturity.
        uint256 positionDuration;
        /// @dev The duration of a checkpoint.
        uint256 checkpointDuration;
        /// @dev A parameter which decreases slippage around a target rate.
        uint256 timeStretch;
        /// @dev The address of the governance contract.
        address governance;
        /// @dev The address which collects governance fees
        address feeCollector;
        /// @dev The address which collects swept tokens.
        address sweepCollector;
        /// @dev The address that will reward checkpoint minters.
        address checkpointRewarder;
        /// @dev The fees applied to trades.
        IHyperdrive.Fees fees;
    }

    struct PoolConfig {
        /// @dev The address of the base token.
        IERC20 baseToken;
        /// @dev The address of the vault shares token.
        IERC20 vaultSharesToken;
        /// @dev The linker factory used by this Hyperdrive instance.
        address linkerFactory;
        /// @dev The hash of the ERC20 linker's code. This is used to derive the
        ///      create2 addresses of the ERC20 linkers used by this instance.
        bytes32 linkerCodeHash;
        /// @dev The initial vault share price.
        uint256 initialVaultSharePrice;
        /// @dev The minimum share reserves.
        uint256 minimumShareReserves;
        /// @dev The minimum amount of tokens that a position can be opened or
        ///      closed with.
        uint256 minimumTransactionAmount;
        /// @dev The maximum delta between the last checkpoint's weighted spot
        ///      APR and the current spot APR for an LP to add liquidity. This
        ///      protects LPs from sandwich attacks.
        uint256 circuitBreakerDelta;
        /// @dev The duration of a position prior to maturity.
        uint256 positionDuration;
        /// @dev The duration of a checkpoint.
        uint256 checkpointDuration;
        /// @dev A parameter which decreases slippage around a target rate.
        uint256 timeStretch;
        /// @dev The address of the governance contract.
        address governance;
        /// @dev The address which collects governance fees
        address feeCollector;
        /// @dev The address which collects swept tokens.
        address sweepCollector;
        /// @dev The address that will reward checkpoint minters.
        address checkpointRewarder;
        /// @dev The fees applied to trades.
        IHyperdrive.Fees fees;
    }

    struct PoolInfo {
        /// @dev The reserves of shares held by the pool.
        uint256 shareReserves;
        /// @dev The adjustment applied to the share reserves when pricing
        ///      bonds. This is used to ensure that the pricing mechanism is
        ///      held invariant under flat updates for security reasons.
        int256 shareAdjustment;
        /// @dev The proceeds in base of the unredeemed matured positions.
        uint256 zombieBaseProceeds;
        /// @dev The shares reserved for unredeemed matured positions.
        uint256 zombieShareReserves;
        /// @dev The reserves of bonds held by the pool.
        uint256 bondReserves;
        /// @dev The total supply of LP shares.
        uint256 lpTotalSupply;
        /// @dev The current vault share price.
        uint256 vaultSharePrice;
        /// @dev An amount of bonds representing outstanding unmatured longs.
        uint256 longsOutstanding;
        /// @dev The average maturity time of the outstanding longs.
        uint256 longAverageMaturityTime;
        /// @dev An amount of bonds representing outstanding unmatured shorts.
        uint256 shortsOutstanding;
        /// @dev The average maturity time of the outstanding shorts.
        uint256 shortAverageMaturityTime;
        /// @dev The amount of withdrawal shares that are ready to be redeemed.
        uint256 withdrawalSharesReadyToWithdraw;
        /// @dev The proceeds recovered by the withdrawal pool.
        uint256 withdrawalSharesProceeds;
        /// @dev The share price of LP shares. This can be used to mark LP
        ///      shares to market.
        uint256 lpSharePrice;
        /// @dev The global exposure of the pool due to open positions
        uint256 longExposure;
    }

    struct Options {
        /// @dev The address that receives the proceeds of a trade or LP action.
        address destination;
        /// @dev A boolean indicating that the trade or LP action should be
        ///      settled in base if true and in the yield source shares if false.
        bool asBase;
        /// @dev Additional data that can be used to implement custom logic in
        ///      implementation contracts.
        bytes extraData;
    }

    /// Getters ///

    /// @notice Gets the target0 address.
    /// @return The target0 address.
    function target0() external view returns (address);

    /// @notice Gets the target1 address.
    /// @return The target1 address.
    function target1() external view returns (address);

    /// @notice Gets the target2 address.
    /// @return The target2 address.
    function target2() external view returns (address);

    /// @notice Gets the target3 address.
    /// @return The target3 address.
    function target3() external view returns (address);
}

interface IHyperdriveLP {
    function getPoolInfo() external view returns (IHyperdrive.PoolInfo memory);

    function balanceOf(uint256 id, address account) external view returns (uint256);
}
