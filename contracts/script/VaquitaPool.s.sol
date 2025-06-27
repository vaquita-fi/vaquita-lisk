// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";

contract VaquitaPoolScript is Script {
    VaquitaPool public vaquita;

    function run() public returns (address) {
        vm.startBroadcast();

        vaquita = new VaquitaPool();

        vm.stopBroadcast();

        return address(vaquita);
    }
}
