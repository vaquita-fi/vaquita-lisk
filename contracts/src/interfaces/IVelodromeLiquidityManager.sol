// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Struct for user deposit tracking
struct Deposit {
    bytes32 id;
    uint256 shares;
    uint256 amount0Contributed;
    uint256 amount1Contributed;
    uint256 amount0Used;
    uint256 amount1Used;
    uint256 amount0Remaining;
    uint256 amount1Remaining;
}

/// @title IVelodromeLiquidityManager
/// @notice Interface for VelodromeLiquidityManager
interface IVelodromeLiquidityManager {
    /// @notice Emitted when a user makes a deposit
    event FundsDeposited(address indexed user, bytes32 indexed depositId, uint256 amountA, uint256 amountB, uint256 shares);
    /// @notice Emitted when a user withdraws
    event FundsWithdrawn(address indexed user, bytes32 indexed depositId, uint256 amountA);

    /**
     * @notice Deposit tokenA, swap half for tokenB, and add liquidity
     * @param _depositId The unique deposit ID
     * @param amount The amount of tokenA to deposit
     * @return sharesToMint The number of shares minted for this deposit
     */
    function deposit(bytes32 _depositId, uint256 amount) external returns (uint256 sharesToMint);

    /**
     * @notice Withdraw a user's deposit, remove liquidity, swap back to tokenA, and transfer to user
     * @param depositId The deposit ID to withdraw
     * @return finalTokenAAmount The final amount of tokenA returned to the user
     */
    function withdraw(bytes32 depositId) external returns (uint256 finalTokenAAmount);

    /**
     * @notice Get a user's deposit struct by depositId
     * @param user The user address
     * @param depositId The deposit ID
     * @return The Deposit struct
     */
    function getUserDeposit(address user, bytes32 depositId) external view returns (Deposit memory);

    /**
     * @notice Get all deposit IDs for a user
     * @param user The user address
     * @return Array of deposit IDs
     */
    function getUserDepositIds(address user) external view returns (bytes32[] memory);
}
