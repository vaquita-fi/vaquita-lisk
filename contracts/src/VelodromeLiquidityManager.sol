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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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
    address public token0;
    address public token1;
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
     * @param _token0 Address of token0
     * @param _token1 Address of token1
     * @param _universalRouter Address of the universal router
     * @param _nonfungiblePositionManager Address of the position manager
     * @param _v3SwapExactIn Swap command byte
     * @param _tickSpacing Tick spacing for the pool
     * @param _tickLower Lower tick for the position
     * @param _tickUpper Upper tick for the position
     */
    function initialize(
        address _token0,
        address _token1,
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
        if (_token0 == address(0) || _token1 == address(0) || _universalRouter == address(0) || _nonfungiblePositionManager == address(0)) revert InvalidAddress();
        require(_token0 < _token1, "The tokens are not sorted");
        token0 = _token0;
        token1 = _token1;
        v3SwapExactIn = _v3SwapExactIn;
        tickSpacing = _tickSpacing;
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        universalRouter = IUniversalRouter(_universalRouter);
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        IERC20(token0).approve(address(universalRouter), type(uint256).max);
        IERC20(token1).approve(address(universalRouter), type(uint256).max);
        IERC20(token0).approve(address(nonfungiblePositionManager), type(uint256).max);
        IERC20(token1).approve(address(nonfungiblePositionManager), type(uint256).max);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
    * @notice Decreases and collects liquidity from the position proportional to the given share amount.
    * @param shares The number of shares to remove from the position.
    * @return collectedAmount0 The amount of token0 collected (includes both fees and liquidity)
    * @return collectedAmount1 The amount of token1 collected (includes both fees and liquidity)
    */
    function _decreaseAndCollectLiquidity(uint256 shares) internal returns (uint256 collectedAmount0, uint256 collectedAmount1) {
        if (totalShares == 0) return (0, 0);
        
        (, , , , , , , uint128 totalPositionLiquidity, , , , ) = nonfungiblePositionManager.positions(positionTokenId);
        uint128 liquidityToRemove = uint128((shares * totalPositionLiquidity) / totalShares);

        DecreaseLiquidityParams memory params = DecreaseLiquidityParams({
            tokenId: positionTokenId,
            liquidity: liquidityToRemove,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // Step 1: Decrease liquidity - this adds the liquidity tokens to tokensOwed
        nonfungiblePositionManager.decreaseLiquidity(params);
        
        // Step 2: Get the updated tokensOwed values (now includes fees + decreased liquidity)
        (, , , , , , , , , , uint128 tokensOwed0, uint128 tokensOwed1) = nonfungiblePositionManager.positions(positionTokenId);
        
        // Step 3: Collect this user's proportional share of ALL available tokens
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            // Calculate this user's share of the total owed tokens
            uint128 amount0ToCollect = uint128((shares * tokensOwed0) / totalShares);
            uint128 amount1ToCollect = uint128((shares * tokensOwed1) / totalShares);
            
            if (amount0ToCollect > 0 || amount1ToCollect > 0) {
                CollectParams memory collectParams = CollectParams({
                    tokenId: positionTokenId,
                    recipient: address(this),
                    amount0Max: amount0ToCollect,
                    amount1Max: amount1ToCollect
                });
                (collectedAmount0, collectedAmount1) = nonfungiblePositionManager.collect(collectParams);
            }
        }
        
        totalShares -= shares;
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
     * @notice Deposit 0, swap half for token1, and add liquidity
     * @param depositId The unique deposit ID
     * @param amountA The amountA of token0 to deposit
     */
    function deposit(bytes16 depositId, address tokenA, uint256 amountA) external nonReentrant whenNotPaused returns (uint256) {
        require(depositId != 0, "Deposit ID cannot be zero");
        require(userDepositDetails[msg.sender][depositId].shares == 0, "Deposit ID already exists for user");
        require(amountA > 0, "Deposit amountA must be greater than 0");

        address tokenB;
        (tokenA, tokenB) = _orderToken(tokenA);

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);

        uint256 swapAmount = amountA / 2;
        uint256 balanceBBefore = IERC20(tokenB).balanceOf(address(this));
        swap(tokenA, tokenB, swapAmount);
        uint256 balanceBAfter = IERC20(tokenB).balanceOf(address(this));
        uint256 amountB = balanceBAfter - balanceBBefore;

        uint256 sharesToMint = _addLiquidity(tokenA, amountA - swapAmount, amountB, msg.sender, depositId);
        emit FundsDeposited(msg.sender, depositId, amountA - swapAmount, amountB, sharesToMint);
        return sharesToMint;
    }

    /**
     * @notice Add liquidity to the pool for a user deposit
     * @param amountA Amount of tokenA
     * @param amountB Amount of tokenB
     * @param depositor The user address
     * @param depositId The deposit ID
     */
    function _addLiquidity(address tokenA, uint256 amountA, uint256 amountB, address depositor, bytes16 depositId) internal returns (uint256) {
        // No need to approve here due to approve-once pattern
        uint256 amount0 = tokenA == token0 ? amountA : amountB;
        uint256 amount1 = tokenA == token0 ? amountB : amountA;
        uint256 sharesToMint;
        uint256 amount0Used;
        uint256 amount1Used;

        if (positionTokenId == 0) {
            // mint a new position when there is no position yet
            MintParams memory params = MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: int24(tickSpacing),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0, 
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPriceX96: 0
            });

            (positionTokenId, sharesToMint, amount0Used, amount1Used) = nonfungiblePositionManager.mint(params);
        } else {
            // add liquidity to an existing position
            (, , , , , , , uint128 totalLiquidity, , , , ) = nonfungiblePositionManager.positions(positionTokenId);

            IncreaseLiquidityParams memory params = IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
            uint256 addedLiquidity;
            (addedLiquidity, amount0Used, amount1Used) = nonfungiblePositionManager.increaseLiquidity(params);
            
            sharesToMint = totalLiquidity > 0 ? (addedLiquidity * totalShares) / totalLiquidity : addedLiquidity;
        }

        totalShares += sharesToMint;
        userDepositDetails[depositor][depositId] = Deposit({
            id: depositId,
            shares: sharesToMint,
            amount0Contributed: amount0,
            amount1Contributed: amount1,
            amount0Used: amount0Used,
            amount1Used: amount1Used,
            amount0Remaining: amount0 - amount0Used,
            amount1Remaining: amount1 - amount1Used,
            isActive: true
        });
        userDepositIds[depositor].push(depositId);
        emit FundsDeposited(depositor, depositId, amount0, amount1, sharesToMint);
        return sharesToMint;
    }

    /**
     * @notice Withdraw a user's deposit, remove liquidity, swap back to token0, and transfer to user
     * @param depositId The deposit ID to withdraw
     */
    function withdraw(bytes16 depositId, address tokenA) external nonReentrant whenNotPaused returns (uint256) {
        Deposit storage depositToWithdraw = userDepositDetails[msg.sender][depositId];
        uint256 shares = depositToWithdraw.shares;
        require(depositToWithdraw.isActive, "Deposit is not active");
        require(depositToWithdraw.id == depositId, "Only deposit owner can withdraw");

        depositToWithdraw.isActive = false;

        (uint256 collectedAmount0, uint256 collectedAmount1) = _decreaseAndCollectLiquidity(shares);

        // Add the unused deposit tokens that were sitting in the contract
        uint256 finalToken0Amount = collectedAmount0 + depositToWithdraw.amount0Remaining;
        uint256 finalToken1Amount = collectedAmount1 + depositToWithdraw.amount1Remaining;

        address tokenB;
        (tokenA, tokenB) = _orderToken(tokenA);

        uint256 finalTokenBAmount = token0 == tokenA ? finalToken1Amount : finalToken0Amount;
        uint256 finalTokenAAmount = token0 == tokenA ? finalToken0Amount : finalToken1Amount;

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
     * @notice Orders the given token address as tokenA and tokenB according to contract's token0 and token1.
     * @dev Returns (token0, token1) if input is token0, or (token1, token0) if input is token1.
     * @param token The token address to order.
     * @return tokenA The primary token (matches input token).
     * @return tokenB The secondary token (the other token in the pair).
     */
    function _orderToken(address token) internal view returns(address tokenA, address tokenB) {
        if (token == token0) {
            return (token0, token1);
        } else if (token == token1) {
            return (token1, token0); // Switch
        } else {
            revert("Wrong token");
        }
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
