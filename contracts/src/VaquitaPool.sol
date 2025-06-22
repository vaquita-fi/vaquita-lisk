// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IUniversalRouter} from "./interfaces/external/IUniversalRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    INonfungiblePositionManager,
    MintParams,
    IncreaseLiquidityParams,
    DecreaseLiquidityParams
} from "./interfaces/external/INonFungiblePositionManager.sol";

struct Deposit {
    bytes16 id;
    uint256 shares;
    uint256 amount0Contributed;
    uint256 amount1Contributed;
}

contract VaquitaPool {
    address public tokenA;
    address public tokenB;
    IUniversalRouter public universalRouter;
    INonfungiblePositionManager public nonfungiblePositionManager;
    uint256 public v3SwapExactIn;
    int24 public tickSpacing;
    int24 public tickLower;
    int24 public tickUpper;

    uint256 public positionTokenId;
    uint256 public totalShares;

    // Track each deposit for every user
    mapping(address => mapping(bytes16 => Deposit)) public userDepositDetails;
    mapping(address => bytes16[]) public userDepositIds;

    constructor(
        address _tokenA,
        address _tokenB,
        address _universalRouter,
        address _nonfungiblePositionManager,
        uint256 _v3SwapExactIn,
        int24 _tickSpacing,
        int24 _tickLower,
        int24 _tickUpper
    ) {
        tokenA = _tokenA;
        tokenB = _tokenB;
        v3SwapExactIn = _v3SwapExactIn;
        tickSpacing = _tickSpacing;
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        universalRouter = IUniversalRouter(_universalRouter);
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
    }

    function deposit(bytes16 _depositId, uint256 amount) public {
        require(_depositId != 0, "Deposit ID cannot be zero");
        require(userDepositDetails[msg.sender][_depositId].shares == 0, "Deposit ID already exists");
        require(amount > 0, "Amount must be greater than 0");
        IERC20(tokenA).transferFrom(msg.sender, address(this), amount);

        uint256 swapAmount = amount / 2;
        
        uint256 balanceBBefore = IERC20(tokenB).balanceOf(address(this));
        swap(swapAmount);
        uint256 balanceBAfter = IERC20(tokenB).balanceOf(address(this));
        uint256 amountB = balanceBAfter - balanceBBefore;

        addLiquidity(amount - swapAmount, amountB, msg.sender, _depositId);
    }

    function swap(uint256 amountIn) public {
        IERC20(tokenA).approve(address(universalRouter), amountIn);
        uint256 amountOutMin = 0;
        bytes memory commands = abi.encodePacked(bytes1(uint8(v3SwapExactIn)));
        bytes memory path = abi.encodePacked(address(tokenA), tickSpacing, address(tokenB));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), amountIn, amountOutMin, path, true);
        universalRouter.execute(commands, inputs, block.timestamp);
    }

    function addLiquidity(uint256 amountA, uint256 amountB, address depositor, bytes16 depositId) internal {
        IERC20(tokenA).approve(address(nonfungiblePositionManager), amountA);
        IERC20(tokenB).approve(address(nonfungiblePositionManager), amountB);

        uint256 sharesToMint;
        uint256 amount0Used;
        uint256 amount1Used;

        if (positionTokenId == 0) {
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
            (, , , , , , , uint128 totalLiquidity, , , , ) = nonfungiblePositionManager.positions(positionTokenId);
            require(totalLiquidity > 0, "Cannot add to empty position");

            IncreaseLiquidityParams memory params = IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amountB,
                amount1Desired: amountA,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
            (uint128 addedLiquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager.increaseLiquidity(params);
            
            sharesToMint = (addedLiquidity * totalShares) / totalLiquidity;
            amount0Used = amount0;
            amount1Used = amount1;
        }

        totalShares += sharesToMint;
        userDepositDetails[depositor][depositId] = Deposit({
            id: depositId,
            shares: sharesToMint,
            amount0Contributed: amount0Used,
            amount1Contributed: amount1Used
        });
        userDepositIds[depositor].push(depositId);
    }

    function withdraw(bytes16 depositId) public {
        Deposit storage depositToWithdraw = userDepositDetails[msg.sender][depositId];
        uint256 shares = depositToWithdraw.shares;
        require(shares > 0, "Deposit not found or already withdrawn");

        (, , , , , , , uint128 totalPositionLiquidity, , , , ) = nonfungiblePositionManager.positions(positionTokenId);
        
        uint128 liquidityToRemove = uint128((shares * totalPositionLiquidity) / totalShares);

        DecreaseLiquidityParams memory params = DecreaseLiquidityParams({
            tokenId: positionTokenId,
            liquidity: liquidityToRemove,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
        
        totalShares -= shares;

        // Delete from mapping
        delete userDepositDetails[msg.sender][depositId];

        // Remove ID from array
        bytes16[] storage ids = userDepositIds[msg.sender];
        for (uint i = 0; i < ids.length; i++) {
            if (ids[i] == depositId) {
                ids[i] = ids[ids.length - 1];
                ids.pop();
                break;
            }
        }

        // amount1 is in tokenA, amount0 is in tokenB (based on our minting order)
        uint256 finalTokenAAmount = amount1;

        // Swap the withdrawn tokenB (amount0) back to tokenA
        if (amount0 > 0) {
            IERC20(tokenB).approve(address(universalRouter), amount0);
            uint256 amountOutMin = 0;
            bytes memory commands = abi.encodePacked(bytes1(uint8(v3SwapExactIn)));
            bytes memory path = abi.encodePacked(address(tokenB), tickSpacing, address(tokenA));
            bytes[] memory inputs = new bytes[](1);

            uint256 tokenABalanceBeforeSwap = IERC20(tokenA).balanceOf(address(this));
            inputs[0] = abi.encode(address(this), amount0, amountOutMin, path, true);
            universalRouter.execute(commands, inputs, block.timestamp);
            uint256 tokenABalanceAfterSwap = IERC20(tokenA).balanceOf(address(this));
            
            uint256 swappedAmountA = tokenABalanceAfterSwap - tokenABalanceBeforeSwap;
            finalTokenAAmount += swappedAmountA;
        }

        // Transfer the precise, combined amount of tokenA back to the user
        if (finalTokenAAmount > 0) {
            IERC20(tokenA).transfer(msg.sender, finalTokenAAmount);
        }
    }

    function getUserDeposit(address user, bytes16 depositId) public view returns (Deposit memory) {
        return userDepositDetails[user][depositId];
    }

    function getUserDepositIds(address user) public view returns (bytes16[] memory) {
        return userDepositIds[user];
    }
}
