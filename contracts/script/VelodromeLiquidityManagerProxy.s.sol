// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {VelodromeLiquidityManager} from "../src/VelodromeLiquidityManager.sol";

contract VelodromeLiquidityManagerProxyScript is Script {
    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address owner = vm.addr(deployerPrivateKey);

        // Deploy implementation
        VelodromeLiquidityManager implementation = new VelodromeLiquidityManager();
        console.log("VelodromeLiquidityManager implementation:", address(implementation));

        // Encode initializer data
        address tokenA = address(0xF242275d3a6527d877f2c927a82D9b057609cc71); // USDC.e
        address tokenB = address(0x05D032ac25d322df992303dCa074EE7392C117b9); // USDT
        address universalRouter = address(0x652e53C6a4FE39B6B30426d9c96376a105C89A95);
        address nonfungiblePositionManager = address(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702);
        uint256 v3SwapExactIn = 0x00;
        int24 tickSpacing = 1;
        int24 tickLower = 3;
        int24 tickUpper = 6;
        bytes memory initData = abi.encodeWithSelector(
            implementation.initialize.selector,
            tokenA,
            tokenB,
            universalRouter,
            nonfungiblePositionManager,
            v3SwapExactIn,
            tickSpacing,
            tickLower,
            tickUpper
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            owner,
            initData
        );
        console.log("VelodromeLiquidityManager proxy:", address(proxy));

        vm.stopBroadcast();

        return address(proxy);
    }
} 