// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {L0BridgeWrapper} from "../src/L0BridgeWrapper.sol";

contract DeployScript is Script {
    function run() external {
        address oft = vm.envAddress("OFT");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast();

        // Deploy implementation
        L0BridgeWrapper impl = new L0BridgeWrapper();
        console.log("Implementation:", address(impl));

        // Deploy proxy
        bytes memory initData = abi.encodeCall(L0BridgeWrapper.initialize, (oft, owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
