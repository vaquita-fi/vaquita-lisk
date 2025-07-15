// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IUniversalRouter} from "./interfaces/external/IUniversalRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    INonfungiblePositionManager,
    MintParams,
    IncreaseLiquidityParams,
    DecreaseLiquidityParams,
    CollectParams
} from "./interfaces/external/INonFungiblePositionManager.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

struct Deposit {
    bytes16 id;
    uint256 shares;
    uint256 amount0Contributed;
    uint256 amount1Contributed;
    uint256 amount0Used;
    uint256 amount1Used;
    uint256 amount0Remaining;
    uint256 amount1Remaining;
    bool isActive;
}

contract VelodromeLiquidityManager is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    address public tokenA;
    address public tokenB;
    IUniversalRouter public universalRouter;
    INonfungiblePositionManager public nonfungiblePositionManager;
    uint8 public v3SwapExactIn;
    int24 public tickSpacing;
    int24 public tickLower;
    int24 public tickUpper;

    uint256 public positionTokenId;
    uint256 public totalShares;

    // Track each deposit for every user
    mapping(address => mapping(bytes16 => Deposit)) public userDepositDetails;
    mapping(address => bytes16[]) public userDepositIds;

    /// @notice Emitted when a user makes a deposit
    event FundsDeposited(address indexed user, bytes16 indexed depositId, uint256 amountA, uint256 amountB, uint256 shares);
    /// @notice Emitted when a user withdraws
    event FundsWithdrawn(address indexed user, bytes16 indexed depositId, uint256 amountA);

    // Errors
    error InvalidAddress();

    /**
     * @notice Contract constructor
     * @param _tokenA Address of tokenA
     * @param _tokenB Address of tokenB
     * @param _universalRouter Address of the universal router
     * @param _nonfungiblePositionManager Address of the position manager
     * @param _v3SwapExactIn Swap command byte
     * @param _tickSpacing Tick spacing for the pool
     * @param _tickLower Lower tick for the position
     * @param _tickUpper Upper tick for the position
     */
    function initialize(
        address _tokenA,
        address _tokenB,
        address _universalRouter,
        address _nonfungiblePositionManager,
        uint8 _v3SwapExactIn,
        int24 _tickSpacing,
        int24 _tickLower,
        int24 _tickUpper
    ) external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        if (_tokenA == address(0) || _tokenB == address(0) || _universalRouter == address(0) || _nonfungiblePositionManager == address(0)) revert InvalidAddress();
        tokenA = _tokenA;
        tokenB = _tokenB;
        v3SwapExactIn = _v3SwapExactIn;
        tickSpacing = _tickSpacing;
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        universalRouter = IUniversalRouter(_universalRouter);
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        IERC20(tokenA).approve(address(universalRouter), type(uint256).max);
        IERC20(tokenB).approve(address(universalRouter), type(uint256).max);
        IERC20(tokenA).approve(address(nonfungiblePositionManager), type(uint256).max);
        IERC20(tokenB).approve(address(nonfungiblePositionManager), type(uint256).max);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Internal helper to decrease and collect liquidity for a given share amount
     * @param shares The shares to remove
     * @return collectedAmount0 Amount of token0 collected
     * @return collectedAmount1 Amount of token1 collected
     * @return liquidityToRemove The liquidity removed
     */
    function _decreaseAndCollectLiquidity(uint256 shares) internal returns (uint256 collectedAmount0, uint256 collectedAmount1, uint128 liquidityToRemove) {
        if (totalShares == 0) return (0, 0, 0);
        (, , , , , , , uint128 totalPositionLiquidity, , , , ) = nonfungiblePositionManager.positions(positionTokenId);
        liquidityToRemove = uint128((shares * totalPositionLiquidity) / totalShares);
        totalShares -= shares;

        DecreaseLiquidityParams memory params = DecreaseLiquidityParams({
            tokenId: positionTokenId,
            liquidity: liquidityToRemove,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // Step 1: Decrease liquidity (this only updates the position, doesn't transfer tokens)
        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
        
        // Step 2: Collect the tokens from the position
        CollectParams memory collectParams = CollectParams({
            tokenId: positionTokenId,
            recipient: address(this), // Collect to this contract first
            amount0Max: SafeCast.toUint128(amount0),
            amount1Max: SafeCast.toUint128(amount1)
        });
        (collectedAmount0, collectedAmount1) = nonfungiblePositionManager.collect(collectParams);
    }

    /**
     * @notice Swaps fromToken to toToken using the universal router
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param amountIn The amount to swap
     */
    function swap(address fromToken, address toToken, uint256 amountIn) internal {
        // No need to approve here due to approve-once pattern
        uint256 amountOutMin = 0;
        bytes memory commands = abi.encodePacked(bytes1(v3SwapExactIn));
        bytes memory path = abi.encodePacked(fromToken, tickSpacing, toToken);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), amountIn, amountOutMin, path, true);
        universalRouter.execute(commands, inputs, block.timestamp);
    }

    /**
     * @notice Deposit tokenA, swap half for tokenB, and add liquidity
     * @param depositId The unique deposit ID
     * @param amount The amount of tokenA to deposit
     */
    function deposit(bytes16 depositId, uint256 amount) external nonReentrant whenNotPaused returns (uint256) {
        require(depositId != 0, "Deposit ID cannot be zero");
        require(userDepositDetails[msg.sender][depositId].shares == 0, "Deposit ID already exists for user");
        require(amount > 0, "Deposit amount must be greater than 0");
        IERC20(tokenA).transferFrom(msg.sender, address(this), amount);

        uint256 swapAmount = amount / 2;
        uint256 balanceBBefore = IERC20(tokenB).balanceOf(address(this));
        swap(tokenA, tokenB, swapAmount);
        uint256 balanceBAfter = IERC20(tokenB).balanceOf(address(this));
        uint256 amountB = balanceBAfter - balanceBBefore;

        uint256 sharesToMint = _addLiquidity(amount - swapAmount, amountB, msg.sender, depositId);
        emit FundsDeposited(msg.sender, depositId, amount - swapAmount, amountB, sharesToMint);
        return sharesToMint;
    }

    /**
     * @notice Add liquidity to the pool for a user deposit
     * @param amountA Amount of tokenA
     * @param amountB Amount of tokenB
     * @param depositor The user address
     * @param depositId The deposit ID
     */
    function _addLiquidity(uint256 amountA, uint256 amountB, address depositor, bytes16 depositId) internal returns (uint256) {
        // No need to approve here due to approve-once pattern
        uint256 sharesToMint;
        uint256 amount0Used;
        uint256 amount1Used;

        if (positionTokenId == 0) {
            // mint a new position when there is no position yet
            MintParams memory params = MintParams({
                token0: tokenB,
                token1: tokenA,
                tickSpacing: int24(tickSpacing),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amountB,
                amount1Desired: amountA,
                amount0Min: 0, 
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPriceX96: 0
            });

            (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager.mint(params);
            positionTokenId = tokenId;
            sharesToMint = liquidity;
            amount0Used = amount0;
            amount1Used = amount1;
        } else {
            // add liquidity to an existing position
            (, , , , , , , uint128 totalLiquidity, , , , ) = nonfungiblePositionManager.positions(positionTokenId);

            IncreaseLiquidityParams memory params = IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amountB,
                amount1Desired: amountA,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
            (uint128 addedLiquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager.increaseLiquidity(params);
            
            sharesToMint = totalLiquidity > 0 ? (addedLiquidity * totalShares) / totalLiquidity : addedLiquidity;
            amount0Used = amount0;
            amount1Used = amount1;
        }

        totalShares += sharesToMint;
        userDepositDetails[depositor][depositId] = Deposit({
            id: depositId,
            shares: sharesToMint,
            amount0Contributed: amountB,
            amount1Contributed: amountA,
            amount0Used: amount0Used,
            amount1Used: amount1Used,
            amount0Remaining: amountB - amount0Used,
            amount1Remaining: amountA - amount1Used,
            isActive: true
        });
        userDepositIds[depositor].push(depositId);
        emit FundsDeposited(depositor, depositId, amountA, amountB, sharesToMint);
        return sharesToMint;
    }

    /**
     * @notice Withdraw a user's deposit, remove liquidity, swap back to tokenA, and transfer to user
     * @param depositId The deposit ID to withdraw
     */
    function withdraw(bytes16 depositId) external nonReentrant whenNotPaused returns (uint256) {
        Deposit storage depositToWithdraw = userDepositDetails[msg.sender][depositId];
        uint256 shares = depositToWithdraw.shares;
        require(depositToWithdraw.isActive, "Deposit is not active");
        require(depositToWithdraw.id == depositId, "Only deposit owner can withdraw");

        depositToWithdraw.isActive = false;

        (uint256 collectedAmount0, uint256 collectedAmount1, ) = _decreaseAndCollectLiquidity(shares);

        uint256 finalTokenAAmount = collectedAmount1 + depositToWithdraw.amount1Remaining;
        uint256 finalTokenBAmount = collectedAmount0 + depositToWithdraw.amount0Remaining;

        if (finalTokenBAmount > 0) {
            uint256 tokenABalanceBeforeSwap = IERC20(tokenA).balanceOf(address(this));
            swap(tokenB, tokenA, finalTokenBAmount);
            uint256 tokenABalanceAfterSwap = IERC20(tokenA).balanceOf(address(this));
            uint256 swappedAmountA = tokenABalanceAfterSwap - tokenABalanceBeforeSwap;
            finalTokenAAmount += swappedAmountA;
        }

        if (finalTokenAAmount > 0) {
            IERC20(tokenA).transfer(msg.sender, finalTokenAAmount);
        }
        emit FundsWithdrawn(msg.sender, depositId, finalTokenAAmount);
        return finalTokenAAmount;
    }

    /**
     * @notice Get a user's deposit struct by depositId
     * @param user The user address
     * @param depositId The deposit ID
     * @return The Deposit struct
     */
    function getUserDeposit(address user, bytes16 depositId) external view returns (Deposit memory) {
        return userDepositDetails[user][depositId];
    }

    /**
     * @notice Get all deposit IDs for a user
     * @param user The user address
     * @return Array of deposit IDs
     */
    function getUserDepositIds(address user) external view returns (bytes16[] memory) {
        return userDepositIds[user];
    }
}
