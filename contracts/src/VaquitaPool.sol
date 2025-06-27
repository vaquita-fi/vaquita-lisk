// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVelodromeLiquidityManager} from "./interfaces/IVelodromeLiquidityManager.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IPermit} from "./interfaces/IPermit.sol";

/**
 * @title VaquitaPool
 * @dev A protocol that allows users to deposit tokens, earn Velodrome LP fees and participate in a reward pool
 */
contract VaquitaPool is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // Position struct to store user position information
    struct Position {
        bytes16 id;
        address owner;
        uint256 amount;
        uint256 shares;
        uint256 entryTime;
        uint256 finalizationTime;
        bool isActive;
    }
    
    // State variables
    IERC20 public token;
    IVelodromeLiquidityManager public liquidityManager;
    
    uint256 public lockPeriod = 1 days;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public earlyWithdrawalFee = 0; // Fee for early withdrawals (initially 0)
    
    uint256 public totalDeposits;
    uint256 public totalShares;
    uint256 public rewardPool;
    uint256 public protocolFees;  // New state variable for protocol fees
    
    // Mappings
    mapping(bytes16 => Position) public positions;
    mapping(address => uint256) public userTotalDeposits;

    // Events
    event FundsDeposited(bytes16 indexed depositId, address indexed owner, uint256 amount, uint256 shares);
    event FundsWithdrawn(bytes16 indexed depositId, address indexed owner, uint256 amount, uint256 reward);
    event RewardDistributed(bytes16 indexed depositId, address indexed owner, uint256 reward);
    event LockPeriodUpdated(uint256 newLockPeriod);
    event EarlyWithdrawalFeeUpdated(uint256 newFee);
    event RewardsAdded(uint256 rewardAmount);
    event ProtocolFeesUpdated(uint256 newProtocolFees);
    event ProtocolFeesWithdrawn(uint256 protocolFees);
    // Errors
    error InvalidAmount();
    error PositionNotFound();
    error PositionAlreadyWithdrawn();
    error WithdrawalTooEarly();
    error NotPositionOwner();
    error InvalidAddress();
    error InvalidFee();
    error InvalidDepositId();
    error DepositAlreadyExists();
    
    function initialize(
        address _token,
        address _liquidityManager,
        uint256 _lockPeriod
    ) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        token = IERC20(_token);
        liquidityManager = IVelodromeLiquidityManager(_liquidityManager);
        lockPeriod = _lockPeriod;
        token.approve(address(liquidityManager), type(uint256).max);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Open a new position in the pool
     * @dev Allows a user to deposit tokens, which are supplied to the VelodromeLiquidityManager. Position is tracked by a unique depositId.
     * @param depositId The unique identifier for the position
     * @param amount The amount of tokens to deposit
     * @param deadline The deadline for the permit signature
     * @param signature The permit signature for token approval
     */
    function deposit(bytes16 depositId, uint256 amount, uint256 deadline, bytes memory signature) external whenNotPaused returns (uint256) {
        if (amount == 0) revert InvalidAmount();
        if (depositId == bytes16(0)) revert InvalidDepositId();
        if (positions[depositId].id != bytes16(0)) revert DepositAlreadyExists();

        try IPermit(address(token)).permit(
            msg.sender, address(this), amount, deadline, signature
        ) {} catch {}

        // Transfer tokens from user
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Velodrome
        uint256 sharesToMint = liquidityManager.deposit(depositId, amount);

        // Create position
        Position storage position = positions[depositId];
        position.id = depositId;
        position.owner = msg.sender;
        position.amount = amount;
        position.shares = sharesToMint;
        position.entryTime = block.timestamp;
        position.finalizationTime = block.timestamp + lockPeriod;
        position.isActive = true;

        // Update user info
        userTotalDeposits[msg.sender] += amount;
        totalDeposits += amount;
        totalShares += sharesToMint;

        emit FundsDeposited(depositId, msg.sender, amount, sharesToMint);
        return sharesToMint;
    }

    /**
     * @notice Withdraw from a position
     * @dev Only the position owner can withdraw. Handles early withdrawal fees and reward distribution.
     * @param depositId The ID of the position to withdraw from
     */
    function withdraw(bytes16 depositId) external whenNotPaused returns (uint256) {
        Position storage position = positions[depositId];
        if (position.id == bytes16(0)) revert PositionNotFound();
        if (!position.isActive) revert PositionAlreadyWithdrawn();
        if (position.owner != msg.sender) revert NotPositionOwner();
        
        // Withdraw from Velodrome and get actual amount received
        uint256 withdrawnAmount = liquidityManager.withdraw(depositId);
        uint256 interest = withdrawnAmount > position.amount ? withdrawnAmount - position.amount : 0;

        // Update position and user info
        position.isActive = false;
        userTotalDeposits[msg.sender] -= position.amount;

        uint256 reward = 0;
        uint256 amountToTransfer = 0;
        if (block.timestamp < position.finalizationTime) {
            // Early withdrawal - calculate fee and add remaining interest to reward pool
            uint256 feeAmount = (interest * earlyWithdrawalFee) / BASIS_POINTS;
            uint256 remainingInterest = interest - feeAmount;
            rewardPool += remainingInterest;  // Only remaining interest goes to reward pool
            protocolFees += feeAmount;        // Fees go to protocol fees
            amountToTransfer = withdrawnAmount - interest;
            totalShares -= position.shares;
            totalDeposits -= position.amount;
            // Transfer only initial deposit to user
            token.safeTransfer(msg.sender, amountToTransfer);
        } else {
            // Late withdrawal - calculate and distribute rewards
            reward = _calculateReward(position.shares);
            amountToTransfer = withdrawnAmount + reward;
            rewardPool -= reward;
            totalShares -= position.shares;
            totalDeposits -= position.amount;
            // Transfer initial deposit + reward to user
            token.safeTransfer(msg.sender, amountToTransfer);
        }

        emit FundsWithdrawn(depositId, msg.sender, position.amount, reward);
        return amountToTransfer;
    }

    /**
     * @notice Get position details
     * @param depositId The ID of the position
     * @return positionOwner The position owner
     * @return positionAmount The position amount
     * @return shares The amount of shares received
     * @return entryTime The entry time
     * @return finalizationTime The finalization time
     * @return positionIsActive Whether the position is active
     */
    function getPosition(bytes16 depositId) external view returns (
        address positionOwner,
        uint256 positionAmount,
        uint256 shares,
        uint256 entryTime,
        uint256 finalizationTime,
        bool positionIsActive
    ) {
        Position storage position = positions[depositId];
        return (
            position.owner,
            position.amount,
            position.shares,
            position.entryTime,
            position.finalizationTime,
            position.isActive
        );
    }

    /**
     * @notice Calculate reward for a position
     * @dev Proportional to the user's deposit amount
     * @param shares The position shares
     * @return The calculated reward
     */
    function _calculateReward(uint256 shares) internal view returns (uint256) {
        if (totalShares == 0) return 0;
        return (rewardPool * shares) / totalShares;
    }

    /**
     * @notice Withdraw protocol fees to the contract owner
     */
    function withdrawProtocolFees() external onlyOwner whenNotPaused {
        protocolFees = 0;
        token.safeTransfer(owner(), protocolFees);
        emit ProtocolFeesWithdrawn(protocolFees);
    }

    /**
     * @notice Add rewards to the reward pool (owner only)
     * @param rewardAmount The amount of rewards to add
     */
    function addRewards(uint256 rewardAmount) external onlyOwner whenNotPaused {
        token.safeTransferFrom(msg.sender, address(this), rewardAmount);
        rewardPool += rewardAmount;
        emit RewardsAdded(rewardAmount);
    }

    /**
     * @notice Update the lock period for new positions
     * @param newLockPeriod The new lock period in seconds
     */
    function updateLockPeriod(uint256 newLockPeriod) external onlyOwner {
        lockPeriod = newLockPeriod;
        emit LockPeriodUpdated(newLockPeriod);
    }

    /**
     * @notice Update the early withdrawal fee (owner only)
     * @param newFee The new fee in basis points (0-10000)
     */
    function updateEarlyWithdrawalFee(uint256 newFee) external onlyOwner {
        if (newFee > BASIS_POINTS) revert InvalidFee();
        earlyWithdrawalFee = newFee;
        emit EarlyWithdrawalFeeUpdated(newFee);
    }
} 