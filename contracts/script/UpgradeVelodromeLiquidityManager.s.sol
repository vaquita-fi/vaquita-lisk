// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeVelodromeLiquidityManagerScript is Script {
    function run(address _proxyAdmin, address _proxy, address _newImplementation) public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ProxyAdmin proxyAdmin = ProxyAdmin(_proxyAdmin);
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(_proxy));

        // Upgrade the proxy to the new implementation (no call data)
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), _newImplementation, "");
        console.log("Proxy upgraded to new implementation:", _newImplementation);

        vm.stopBroadcast();

        return address(proxy);
    }
} 