// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VelodromeLiquidityManagerProxyScript} from "../script/VelodromeLiquidityManagerProxy.s.sol";
import {DeployVaquitaPoolProxyScript} from "../script/DeployVaquitaPoolLisk.s.sol";
import {VelodromeLiquidityManagerScript} from "../script/VelodromeLiquidityManager.s.sol";
import {VaquitaPoolScript} from "../script/VaquitaPool.s.sol";
import {UpgradeVelodromeLiquidityManagerScript} from "../script/UpgradeVelodromeLiquidityManager.s.sol";
import {UpgradeVaquitaPoolScript} from "../script/UpgradeVaquitaPool.s.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";
import {TestUtils} from "./TestUtils.sol";

contract ScriptRunTest is TestUtils {

    function setUp() public {
        // Fork mainnet
        uint256 liskForkBlock = 17_998_944;
        vm.createSelectFork(vm.rpcUrl("lisk"), liskForkBlock);
    }

    function test_VelodromeLiquidityManagerProxyScriptRun() public {
        VelodromeLiquidityManagerProxyScript script = new VelodromeLiquidityManagerProxyScript();
        address liquidityManager = script.run();
        assertNotEq(liquidityManager, address(0), "Liquidity manager should be deployed");
    }

    function test_VaquitaPoolProxyScriptRun() public {
        VelodromeLiquidityManagerProxyScript velodromeLiquidityManagerProxyScript = new VelodromeLiquidityManagerProxyScript();
        address liquidityManager = velodromeLiquidityManagerProxyScript.run();
        assertNotEq(liquidityManager, address(0), "Liquidity manager should be deployed");
        DeployVaquitaPoolProxyScript vaquitaPoolProxyScript = new DeployVaquitaPoolProxyScript();
        address vaquitaPool = vaquitaPoolProxyScript.run(liquidityManager);
        assertNotEq(vaquitaPool, address(0), "Vaquita pool should be deployed");
    }

    function test_VelodromeLiquidityManagerScriptRun() public {
        VelodromeLiquidityManagerScript script = new VelodromeLiquidityManagerScript();
        address liquidityManager = script.run();
        assertNotEq(liquidityManager, address(0), "Liquidity manager should be deployed");
    }

    function test_VaquitaPoolScriptRun() public {
        VaquitaPoolScript script = new VaquitaPoolScript();
        address vaquitaPool = script.run();
        assertNotEq(vaquitaPool, address(0), "Vaquita pool should be deployed");
    }

    function test_UpgradeVelodromeLiquidityManagerScriptRun() public {
        VelodromeLiquidityManagerProxyScript velodromeLiquidityManagerProxyScript = new VelodromeLiquidityManagerProxyScript();
        address liquidityManager = velodromeLiquidityManagerProxyScript.run();
        assertNotEq(liquidityManager, address(0), "Liquidity manager should be deployed");

        UpgradeVelodromeLiquidityManagerScript upgradeVelodromeLiquidityManagerScript = new UpgradeVelodromeLiquidityManagerScript();

        VelodromeLiquidityManagerScript velodromeLiquidityManagerScript = new VelodromeLiquidityManagerScript();
        address newLiquidityManager = velodromeLiquidityManagerScript.run();
        address proxyAdminAddress = _getProxyAdmin(address(liquidityManager));

        // Run the upgrade with the admin private key and address
        upgradeVelodromeLiquidityManagerScript.run(proxyAdminAddress, address(liquidityManager), address(newLiquidityManager));
        address upgradedLiquidityManager = upgradeVelodromeLiquidityManagerScript.run(proxyAdminAddress, address(liquidityManager), address(newLiquidityManager));
        assertNotEq(upgradedLiquidityManager, address(0), "Liquidity manager should be deployed");
    }

    function test_UpgradeVaquitaPoolScriptRun() public {
        VelodromeLiquidityManagerProxyScript velodromeLiquidityManagerProxyScript = new VelodromeLiquidityManagerProxyScript();
        address liquidityManager = velodromeLiquidityManagerProxyScript.run();
        assertNotEq(liquidityManager, address(0), "Liquidity manager should be deployed");

        DeployVaquitaPoolProxyScript vaquitaPoolProxyScript = new DeployVaquitaPoolProxyScript();
        address vaquitaPool = vaquitaPoolProxyScript.run(liquidityManager);
        assertNotEq(vaquitaPool, address(0), "Vaquita pool should be deployed");

        VaquitaPoolScript vaquitaPoolScript = new VaquitaPoolScript();
        address newVaquitaPool = vaquitaPoolScript.run();
        assertNotEq(newVaquitaPool, address(0), "New vaquita pool should be deployed");

        UpgradeVaquitaPoolScript upgradeVaquitaPoolScript = new UpgradeVaquitaPoolScript();

        address proxyAdminAddress = _getProxyAdmin(address(vaquitaPool));

        // Run the upgrade with the admin private key and address
        address upgradedVaquitaPool = upgradeVaquitaPoolScript.run(proxyAdminAddress, address(vaquitaPool), address(newVaquitaPool));
        assertNotEq(upgradedVaquitaPool, address(0), "Upgraded vaquita pool should be deployed");
    }
} 