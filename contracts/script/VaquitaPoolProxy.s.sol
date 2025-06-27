// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract VaquitaPoolProxyScript is Script {
    function run() public returns (address) {
        vm.startBroadcast();

        // Deploy implementation
        VaquitaPool implementation = new VaquitaPool();
        console.log("VaquitaPool implementation:", address(implementation));

        // Encode initializer data
        address token = address(0xF242275d3a6527d877f2c927a82D9b057609cc71);
        address liquidityManager = address(0x0000000000000000000000000000000000000000);
        uint256 lockPeriod = 1 days;
        bytes memory initData = abi.encodeWithSelector(
            implementation.initialize.selector,
            token,
            liquidityManager,
            lockPeriod
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(this),
            initData
        );
        console.log("VaquitaPool proxy:", address(proxy));

        vm.stopBroadcast();

        return address(proxy);
    }
} 