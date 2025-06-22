// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {VaquitaPool} from "../src/VaquitaPool.sol";

contract VaquitaPoolScript is Script {
    VaquitaPool public vaquita;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        vaquita = new VaquitaPool(
            address(0xF242275d3a6527d877f2c927a82D9b057609cc71),
            address(0x05D032ac25d322df992303dCa074EE7392C117b9),
            address(0x652e53C6a4FE39B6B30426d9c96376a105C89A95),
            address(0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702),
            0x00,
            1,
            23,
            26
        );

        vm.stopBroadcast();
    }
}
