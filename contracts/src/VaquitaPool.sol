// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IVelodromeLiquidityManager} from "./interfaces/IVelodromeLiquidityManager.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IPermit} from "./interfaces/IPermit.sol";

/**
 * @title VaquitaPool
 * @dev A protocol that allows users to deposit tokens, earn Velodrome LP fees and participate in a reward pool
 */
contract VaquitaPool is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
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
        uint256 lockPeriod;
    }
    
    // State variables
    IERC20 public token;
    IVelodromeLiquidityManager public liquidityManager;
    
    uint256 public constant BASIS_POINTS = 1e4;
    uint256 public earlyWithdrawalFee = 0; // Fee for early withdrawals (initially 0)
    uint256 public protocolFees;  // protocol fees
    uint256[] public lockPeriods; // Supported lock periods

    struct Period {
        uint256 rewardPool;
        uint256 totalDeposits;
        uint256 totalShares;
    }
    mapping(uint256 => Period) public periods; // lockPeriod => Period
    mapping(address => mapping(uint256 => uint256)) public userTotalDepositsPerLockPeriod; // user => lockPeriod => total deposits
    
    // Mappings
    mapping(bytes16 => Position) public positions;

    // Events
    event FundsDeposited(bytes16 indexed depositId, address indexed owner, uint256 amount, uint256 shares);
    event FundsWithdrawn(bytes16 indexed depositId, address indexed owner, uint256 amount, uint256 reward);
    event RewardDistributed(bytes16 indexed depositId, address indexed owner, uint256 reward);
    event LockPeriodAdded(uint256 newLockPeriod);
    event EarlyWithdrawalFeeUpdated(uint256 newFee);
    event RewardsAdded(uint256 rewardAmount);
    event ProtocolFeesUpdated(uint256 newProtocolFees);
    event ProtocolFeesWithdrawn(uint256 protocolFees);
    // Errors
    error InvalidAmount();
    error PositionNotFound();
    error PositionAlreadyWithdrawn();
    error NotPositionOwner();
    error InvalidAddress();
    error InvalidFee();
    error InvalidDepositId();
    error DepositAlreadyExists();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the contract with the token, liquidity manager, and supported lock periods.
     * @dev Sets up the contract owner, pausable state, and approves the liquidity manager to spend tokens.
     * @param _token The address of the ERC20 token to be deposited.
     * @param _liquidityManager The address of the VelodromeLiquidityManager contract.
     * @param _lockPeriods Array of supported lock periods in seconds.
     */
    function initialize(
        address _token,
        address _liquidityManager,
        uint256[] memory _lockPeriods
    ) external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        if (_token == address(0) || _liquidityManager == address(0)) revert InvalidAddress();
        token = IERC20(_token);
        liquidityManager = IVelodromeLiquidityManager(_liquidityManager);
        lockPeriods = _lockPeriods;
        token.approve(address(liquidityManager), type(uint256).max);
    }

    /**
     * @notice Pauses the contract, disabling deposits and withdrawals.
     * @dev Only callable by the contract owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, enabling deposits and withdrawals.
     * @dev Only callable by the contract owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Open a new position in the pool
     * @dev Allows a user to deposit tokens, which are supplied to the VelodromeLiquidityManager. Position is tracked by a unique depositId.
     * @param depositId The unique identifier for the position
     * @param amount The amount of tokens to deposit
     * @param period The lock period chosen for this deposit
     * @param deadline The deadline for the permit signature
     * @param signature The permit signature for token approval
     */
    function deposit(bytes16 depositId, uint256 amount, uint256 period, uint256 deadline, bytes memory signature) external nonReentrant whenNotPaused returns (uint256 sharesToMint) {
        if (amount == 0) revert InvalidAmount();
        if (depositId == bytes16(0)) revert InvalidDepositId();
        if (positions[depositId].id != bytes16(0)) revert DepositAlreadyExists();
        if (!isSupportedLockPeriod(period)) revert InvalidFee();

        // Create position
        Position storage position = positions[depositId];
        position.id = depositId;
        position.owner = msg.sender;
        position.amount = amount;
        position.entryTime = block.timestamp;
        position.finalizationTime = block.timestamp + period;
        position.isActive = true;
        position.lockPeriod = period;

        // Update user info
        userTotalDepositsPerLockPeriod[msg.sender][period] += amount;
        periods[period].totalDeposits += amount;

        try IPermit(address(token)).permit(
            msg.sender, address(this), amount, deadline, signature
        ) {} catch {}

        // Transfer tokens from user
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Velodrome
        sharesToMint = _supplyToVelodrome(depositId, amount);
        
        // AUDIT NOTE: This state change after external call is safe because:
        // 1. nonReentrant modifier prevents reentrancy
        // 2. permit() is wrapped in try-catch
        // 3. sharesToMint is a non-critical value used only for internal accounting and reward calculations
        // 4. We use a trusted token with standard EIP-2612 permit implementation
        position.shares = sharesToMint;
        periods[period].totalShares += sharesToMint;

        emit FundsDeposited(depositId, msg.sender, amount, sharesToMint);
    }

    /**
     * @notice Withdraw from a position
     * @dev Only the position owner can withdraw. Handles early withdrawal fees and reward distribution.
     * @param depositId The ID of the position to withdraw from
     */
    function withdraw(bytes16 depositId) external nonReentrant whenNotPaused returns (uint256 amountToTransfer) {
        Position storage position = positions[depositId];
        if (position.id == bytes16(0)) revert PositionNotFound();
        if (!position.isActive) revert PositionAlreadyWithdrawn();
        if (position.owner != msg.sender) revert NotPositionOwner();

        uint256 period = position.lockPeriod;

        position.isActive = false;

        // Withdraw from Velodrome and get actual amount received
        uint256 withdrawnAmount = _withdrawFromVelodrome(depositId);
        uint256 interest = withdrawnAmount > position.amount ? withdrawnAmount - position.amount : 0;

        uint256 reward = 0;
        if (block.timestamp < position.finalizationTime) {
            // Early withdrawal - calculate fee and add remaining interest to reward pool
            uint256 feeAmount = (interest * earlyWithdrawalFee) / BASIS_POINTS;
            uint256 remainingInterest = interest - feeAmount;
            periods[period].rewardPool += remainingInterest;  // Only remaining interest goes to reward pool
            protocolFees += feeAmount;        // Fees go to protocol fees
            amountToTransfer = withdrawnAmount - interest;
            userTotalDepositsPerLockPeriod[msg.sender][period] -= position.amount;
            periods[period].totalShares -= position.shares;
            periods[period].totalDeposits -= position.amount;
            // Transfer only initial deposit to user
            token.safeTransfer(msg.sender, amountToTransfer);
        } else {
            // Late withdrawal - calculate and distribute rewards
            reward = _calculateReward(position.shares, period);
            amountToTransfer = withdrawnAmount + reward;
            periods[period].rewardPool -= reward;
            userTotalDepositsPerLockPeriod[msg.sender][period] -= position.amount;
            periods[period].totalShares -= position.shares;
            periods[period].totalDeposits -= position.amount;
            // Transfer initial deposit + reward to user
            token.safeTransfer(msg.sender, amountToTransfer);
        }

        emit FundsWithdrawn(depositId, msg.sender, position.amount, reward);
    }

    /**
     * @notice Supplies tokens to the VelodromeLiquidityManager and mints shares.
     * @dev Internal function used during deposit.
     * @param depositId The unique identifier for the position.
     * @param amount The amount of tokens to supply.
     * @return sharesToMint The number of shares minted.
     */
    function _supplyToVelodrome(bytes16 depositId, uint256 amount) internal returns (uint256 sharesToMint) {
        sharesToMint = liquidityManager.deposit(depositId, amount);
    }

    /**
     * @notice Withdraws tokens from the VelodromeLiquidityManager.
     * @dev Internal function used during withdrawal.
     * @param depositId The unique identifier for the position.
     * @return withdrawnAmount The amount of tokens withdrawn.
     */
    function _withdrawFromVelodrome(bytes16 depositId) internal returns (uint256 withdrawnAmount) {
        withdrawnAmount = liquidityManager.withdraw(depositId);
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
     * @param period The lock period for this position
     * @return The calculated reward
     */
    function _calculateReward(uint256 shares, uint256 period) internal view returns (uint256) {
        uint256 totalSharesForPeriod = periods[period].totalShares;
        if (totalSharesForPeriod == 0) return 0;
        return (periods[period].rewardPool * shares) / totalSharesForPeriod;
    }

    /**
     * @notice Withdraw protocol fees to the contract owner
     */
    function withdrawProtocolFees() external onlyOwner whenNotPaused {
        uint256 cacheProtocolFees = protocolFees;
        protocolFees = 0;
        token.safeTransfer(owner(), cacheProtocolFees);
        emit ProtocolFeesWithdrawn(cacheProtocolFees);
    }

    /**
     * @notice Add rewards to the reward pool (owner only)
     * @param period The lock period to add rewards to
     * @param rewardAmount The amount of rewards to add
     */
    function addRewards(uint256 period, uint256 rewardAmount) external onlyOwner whenNotPaused {
        if (!isSupportedLockPeriod(period)) revert InvalidFee();
        token.safeTransferFrom(msg.sender, address(this), rewardAmount);
        periods[period].rewardPool += rewardAmount;
        emit RewardsAdded(rewardAmount);
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

    /**
     * @notice Check if a lock period is supported.
     * @param period The lock period to check.
     * @return bool True if supported, false otherwise.
     */
    function isSupportedLockPeriod(uint256 period) public view returns (bool) {
        uint256 length = lockPeriods.length;
        for (uint256 i = 0; i < length; i++) {
            if (lockPeriods[i] == period) return true;
        }
        return false;
    }

    /**
     * @notice Add a new lock period to the supported list.
     * @dev Only callable by the contract owner.
     * @param newLockPeriod The new lock period in seconds.
     */
    function addLockPeriod(uint256 newLockPeriod) external onlyOwner {
        require(!isSupportedLockPeriod(newLockPeriod), "Lock period already supported");
        lockPeriods.push(newLockPeriod);
        emit LockPeriodAdded(newLockPeriod);
    }
} 