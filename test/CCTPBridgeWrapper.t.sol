// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CCTPBridgeWrapper} from "../src/CCTPBridgeWrapper.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract CCTPBridgeWrapperTest is Test {
    CCTPBridgeWrapper public wrapper;
    CCTPBridgeWrapper public implementation;
    
    // Polygon mainnet addresses (for fork testing)
    address constant POLYGON_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant POLYGON_TOKEN_MESSENGER = 0x9daF8c91AEFAE50b9c0E69629D3F6Ca40cA3B3FE;
    address constant POLYGON_MESSAGE_TRANSMITTER = 0xF3be9355363857F3e001be68856A2f96b4C39Ba9;
    
    // Arbitrum mainnet addresses
    address constant ARBITRUM_MESSAGE_TRANSMITTER = 0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca;
    
    address owner = address(0x1);
    address user = address(0x2);

    function setUp() public {
        // Deploy implementation
        implementation = new CCTPBridgeWrapper();
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            CCTPBridgeWrapper.initialize.selector,
            POLYGON_TOKEN_MESSENGER,
            POLYGON_MESSAGE_TRANSMITTER,
            POLYGON_USDC,
            owner
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        wrapper = CCTPBridgeWrapper(address(proxy));
    }

    function test_Initialize() public view {
        assertEq(address(wrapper.usdc()), POLYGON_USDC);
        assertEq(address(wrapper.tokenMessenger()), POLYGON_TOKEN_MESSENGER);
        assertEq(address(wrapper.messageTransmitter()), POLYGON_MESSAGE_TRANSMITTER);
        assertEq(wrapper.bridgeFee(), 0);
        assertEq(wrapper.feeRecipient(), owner);
    }

    function test_QuoteFee() public view {
        uint256 amount = 100e6; // 100 USDC
        uint256 fee = wrapper.quoteFee(amount);
        assertEq(fee, 0); // Phase 1: free
    }

    function test_SetFee() public {
        vm.prank(owner);
        wrapper.setFee(50); // 0.5%
        assertEq(wrapper.bridgeFee(), 50);
    }

    function test_SetFee_RevertIfTooHigh() public {
        vm.prank(owner);
        vm.expectRevert();
        wrapper.setFee(1001); // > 10%
    }

    function test_SetFee_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        wrapper.setFee(50);
    }

    // Fork test - requires Polygon RPC
    function testFork_BridgeUSDC() public {
        // Skip if not running fork test
        if (block.chainid != 137) {
            return;
        }
        
        // This would require forking Polygon mainnet and giving user some USDC
        // Example:
        // vm.createSelectFork("https://polygon-rpc.com");
        // deal(POLYGON_USDC, user, 100e6);
        // vm.prank(user);
        // IERC20(POLYGON_USDC).approve(address(wrapper), 100e6);
        // uint64 nonce = wrapper.bridgeUSDC(100e6, 3, user);
        // assertGt(nonce, 0);
    }
}
