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
    event FundsDeposited(address indexed user, bytes16 indexed depositId, uint256 amountA, uint256 amountB, uint256 shares);
    /// @notice Emitted when a user withdraws
    event FundsWithdrawn(address indexed user, bytes16 indexed depositId, uint256 amountA);

    /**
     * @notice Deposit tokenA, swap half for tokenB, and add liquidity
     * @param _depositId The unique deposit ID
     * @param amount The amount of tokenA to deposit
     * @return sharesToMint The number of shares minted for this deposit
     */
    function deposit(bytes16 _depositId, address token, uint256 amount) external returns (uint256 sharesToMint);

    /**
     * @notice Withdraw a user's deposit, remove liquidity, swap back to tokenA, and transfer to user
     * @param depositId The deposit ID to withdraw
     * @return finalTokenAAmount The final amount of tokenA returned to the user
     */
    function withdraw(bytes16 depositId, address token) external returns (uint256 finalTokenAAmount);
}
