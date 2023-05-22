// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IAlgebraPool
/// @dev Copied from: https://github.com/cryptoalgebra/Algebra/blob/master/src/core/contracts/interfaces/pool/IAlgebraPoolState.sol
interface IAlgebraPool {
    /**
     * @notice The globalState structure in the pool stores many values but requires only one slot
     * and is exposed as a single method to save gas when accessed externally.
     * @return price The current price of the pool as a sqrt(token1/token0) Q64.96 value;
     * Returns tick The current tick of the pool, i.e. according to the last tick transition that was run;
     * Returns This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(price) if the price is on a tick
     * boundary;
     * Returns fee The last pool fee value in hundredths of a bip, i.e. 1e-6;
     * Returns timepointIndex The index of the last written timepoint;
     * Returns communityFeeToken0 The community fee percentage of the swap fee in thousandths (1e-3) for token0;
     * Returns communityFeeToken1 The community fee percentage of the swap fee in thousandths (1e-3) for token1;
     * Returns unlocked Whether the pool is currently locked to reentrancy;
     */
    function globalState()
        external
        view
        returns (
            uint160 price,
            int24 tick,
            uint16 fee,
            uint16 timepointIndex,
            uint8 communityFeeToken0,
            uint8 communityFeeToken1,
            bool unlocked
        );
}
