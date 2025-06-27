// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";

contract VaquitaPoolScript is Script {
    VaquitaPool public vaquita;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        vaquita = new VaquitaPool();

        vm.stopBroadcast();
    }
}
