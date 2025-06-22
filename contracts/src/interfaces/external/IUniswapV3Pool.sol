// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title The interface for a Uniswap V3 Pool
/// @notice A Uniswap pool facilitates swapping and providing liquidity between two assets
interface IUniswapV3Pool {
    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method for efficiency.
    /// @return sqrtPriceX96 The current price of the pool as a Q64.96 fixed point number
    /// @return tick The current tick of the pool, i.e. log base 1.0001 of the current price
    /// @return observationIndex The index of the last oracle observation that was written,
    /// @return observationCardinality The number of initialized observations that are currently tracked by the pool
    /// @return observationCardinalityNext The next number of observations to track, updated when observations are tracked
    /// @return feeProtocol The protocol fee for both tokens of the pool.
    /// @return unlocked Whether the pool is currently locked to reentrancy
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
} 