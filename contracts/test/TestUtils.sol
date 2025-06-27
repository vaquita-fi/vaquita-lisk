// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "../src/interfaces/external/IUniversalRouter.sol";
import {console} from "forge-std/console.sol";
import {IVelodromeLiquidityManager} from "../src/interfaces/IVelodromeLiquidityManager.sol";

abstract contract TestUtils is Test {
    /// @notice Generates mock fees by performing a swap from tokenA to tokenB using the universal router
    function generateSwapFees(
        address whale,
        IERC20 tokenA,
        IERC20 tokenB,
        address universalRouter,
        uint256 v3SwapExactIn,
        int24 tickSpacing,
        uint256 swapAmount
    ) public {
        // Impersonate whale and perform a swap to generate fees
        vm.startPrank(whale);
        tokenA.approve(universalRouter, swapAmount);
        uint256 whaleUSDCBefore = tokenA.balanceOf(whale);
        uint256 whaleUSDTBefore = tokenB.balanceOf(whale);
        console.log("Whale USDC.e before swap:", whaleUSDCBefore);
        console.log("Whale USDT before swap:", whaleUSDTBefore);
        bytes memory commands = abi.encodePacked(bytes1(uint8(v3SwapExactIn)));
        bytes memory path = abi.encodePacked(address(tokenA), tickSpacing, address(tokenB));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(whale, swapAmount, 0, path, true);
        try IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + 1 hours) {
            console.log("Whale swap executed successfully");
        } catch Error(string memory reason) {
            console.log("Whale swap failed:", reason);
        } catch {
            console.log("Whale swap failed with unknown error");
        }
        uint256 whaleUSDCAfter = tokenA.balanceOf(whale);
        uint256 whaleUSDTAfter = tokenB.balanceOf(whale);
        console.log("Whale USDC.e after swap:", whaleUSDCAfter);
        console.log("Whale USDT after swap:", whaleUSDTAfter);
        console.log("USDC.e swapped:", whaleUSDCBefore - whaleUSDCAfter);
        console.log("USDT received:", whaleUSDTAfter - whaleUSDTBefore);
        vm.stopPrank();
    }

    /// @notice Mocks a call to a contract with a given selector, params, and return value
    function mockCallWithParams(
        address contractToMock,
        bytes4 selector,
        bytes memory params,
        bytes memory returnValue
    ) public {
        vm.mockCall(
            contractToMock,
            abi.encodePacked(selector, params),
            returnValue
        );
    }

    /// @notice Funds a recipient contract with the required amount of tokens from a specified funder
    function fundWithTokens(
        IERC20 token,
        address funder,
        address recipient,
        uint256 amount
    ) public {
        vm.startPrank(funder);
        token.transfer(recipient, amount);
        vm.stopPrank();
    }
} 