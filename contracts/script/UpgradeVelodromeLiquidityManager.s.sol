// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeVelodromeLiquidityManagerScript is Script {
    function run() public {
        vm.startBroadcast();

        // Set these addresses before running the script
        address proxyAdminAddr = address(0x0000000000000000000000000000000000000000);
        address proxyAddr = address(0x0000000000000000000000000000000000000000);
        address newImplementation = address(0x0000000000000000000000000000000000000000);

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(proxyAddr));

        // Upgrade the proxy to the new implementation (no call data)
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), newImplementation, "");
        console.log("Proxy upgraded to new implementation:", newImplementation);

        vm.stopBroadcast();
    }
} 