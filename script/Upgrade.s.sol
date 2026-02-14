// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {L0BridgeWrapper} from "../src/L0BridgeWrapper.sol";

contract UpgradeScript is Script {
    function run() external {
        address proxy = vm.envAddress("WRAPPER");

        vm.startBroadcast();

        // Deploy new implementation
        L0BridgeWrapper newImpl = new L0BridgeWrapper();
        console.log("New implementation:", address(newImpl));

        // Upgrade proxy to new implementation
        L0BridgeWrapper(payable(proxy)).upgradeToAndCall(address(newImpl), "");
        console.log("Proxy upgraded:", proxy);

        vm.stopBroadcast();
    }
}
