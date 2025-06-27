// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {VelodromeLiquidityManager} from "../src/VelodromeLiquidityManager.sol";

contract VelodromeLiquidityManagerScript is Script {
    VelodromeLiquidityManager public liquidityManager;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        liquidityManager = new VelodromeLiquidityManager();

        vm.stopBroadcast();
    }
}
