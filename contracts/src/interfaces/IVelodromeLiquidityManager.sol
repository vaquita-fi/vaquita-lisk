// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IVelodromeLiquidityManager
/// @notice Interface for VelodromeLiquidityManager
interface IVelodromeLiquidityManager {
    /// @notice Struct for user deposit tracking
    struct Deposit {
        uint256 shares;
        uint256 amount0Remaining;
        uint256 amount1Remaining;
        bool isActive;
    }

    /// @notice Emitted when a user makes a deposit
    event FundsDeposited(address indexed user, bytes32 indexed depositId, uint256 amountA, uint256 amountB, uint256 shares);
    /// @notice Emitted when a user withdraws
    event FundsWithdrawn(address indexed user, bytes32 indexed depositId, uint256 amountA);

    function token0() external view returns (address);
    function token1() external view returns (address);

    /**
     * @notice Deposit tokenA, swap half for tokenB, and add liquidity
     * @param _depositId The unique deposit ID
     * @param token The token to deposit
     * @param amount The amount of tokenA to deposit
     * @param amountOutMin The minimum amount of tokenB to receive
     * @param amount0Min The minimum amount of token0 to receive
     * @param amount1Min The minimum amount of token1 to receive
     * @param deadline The deadline for the swap
     * @return sharesToMint The number of shares minted for this deposit
     */
    function deposit(bytes32 _depositId, address token, uint256 amount, uint256 amountOutMin, uint256 amount0Min, uint256 amount1Min, uint256 deadline) external returns (uint256 sharesToMint);

    /**
     * @notice Withdraw a user's deposit, remove liquidity, swap back to tokenA, and transfer to user
     * @param depositId The deposit ID to withdraw
     * @param amountOutMin The minimum amount of tokenA to receive
     * @param amount0Min The minimum amount of token0 to receive
     * @param amount1Min The minimum amount of token1 to receive
     * @param deadline The deadline for the swap
     * @return finalTokenAAmount The final amount of tokenA returned to the user
     */
    function withdraw(bytes32 depositId, address token, uint256 amountOutMin, uint256 amount0Min, uint256 amount1Min, uint256 deadline) external returns (uint256 finalTokenAAmount);
}
