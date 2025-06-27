// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";
import {VelodromeLiquidityManager} from "../src/VelodromeLiquidityManager.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract ProxyDeploymentAndUpgradeTest is Test {
    address tokenA = address(0xF242275d3a6527d877f2c927a82D9b057609cc71);
    address tokenB = address(0x05D032ac25d322df992303dCa074EE7392C117b9);
    address universalRouter = address(0x652e53C6a4FE39B6B30426d9c96376a105C89A95);
    address nonfungiblePositionManager = address(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702);
    uint256 v3SwapExactIn = 0x00;
    int24 tickSpacing = 1;
    int24 tickLower = 3;
    int24 tickUpper = 6;
    uint256 lockPeriod = 1 days;
    VelodromeLiquidityManager proxiedLiquidityManager;
    TransparentUpgradeableProxy proxyLiquidityManager;

    function setUp() public {
        uint256 liskForkBlock = 17_998_944;
        vm.createSelectFork(vm.rpcUrl("lisk"), liskForkBlock);

        VelodromeLiquidityManager implementation = new VelodromeLiquidityManager();
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
        proxyLiquidityManager = new TransparentUpgradeableProxy(
            address(implementation),
            address(this),
            initData
        );
        VelodromeLiquidityManager proxied = VelodromeLiquidityManager(address(proxyLiquidityManager));
        assertEq(proxied.tokenA(), tokenA, "tokenA should be set");
        assertEq(proxied.tokenB(), tokenB, "tokenB should be set");
    }

    // Helper function to get the ProxyAdmin address from a TransparentUpgradeableProxy
    function _getProxyAdmin(address proxy) internal view returns (address) {
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminBytes = vm.load(proxy, adminSlot);
        return address(uint160(uint256(adminBytes)));
    }

    function test_VelodromeLiquidityManagerUpgrade() public {
        address proxyAdminAddress = _getProxyAdmin(address(proxyLiquidityManager));
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        assertEq(proxyAdmin.owner(), address(this), "ProxyAdmin owner should be deployer");
        VelodromeLiquidityManager newImpl = new VelodromeLiquidityManager();
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxyLiquidityManager)),
            address(newImpl),
            ""
        );
        VelodromeLiquidityManager proxied = VelodromeLiquidityManager(address(proxyLiquidityManager));
        assertEq(proxied.tokenA(), tokenA, "tokenA should still be set after upgrade");
        assertEq(proxied.tokenB(), tokenB, "tokenB should still be set after upgrade");
    }

    function test_VaquitaPoolProxyDeploymentAndUpgrade() public {
        VaquitaPool implementation = new VaquitaPool();
        bytes memory initData = abi.encodeWithSelector(
            implementation.initialize.selector,
            tokenA,
            address(proxyLiquidityManager),
            lockPeriod
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this),
            initData
        );
        VaquitaPool proxied = VaquitaPool(address(proxy));
        assertEq(proxied.lockPeriod(), lockPeriod, "Lock period should be set");

        address proxyAdminAddress = _getProxyAdmin(address(proxy));
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        VaquitaPool newImpl = new VaquitaPool();
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(newImpl),
            ""
        );
        assertEq(proxyAdmin.owner(), address(this), "ProxyAdmin owner should be test contract");
        assertEq(proxied.lockPeriod(), lockPeriod, "Lock period should still be set after upgrade");
        assertEq(address(proxied.token()), address(tokenA), "tokenA should be set");
        assertEq(address(proxied.liquidityManager()), address(proxyLiquidityManager), "liquidityManager should be set");
        assertEq(proxied.lockPeriod(), lockPeriod, "lockPeriod should be set");
    }
}