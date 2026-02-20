# Circle CCTP Bridge Wrapper - Implementation Plan

## 目标

参考 `L0BridgeWrapper` 的设计，为 Circle CCTP 创建一个简化的桥接合约：
- 用户只需调用一次 `bridge()`
- 自动处理手续费（类似 LayerZero 的 quote + send 模式）
- UUPS 可升级

---

## Phase 1: MVP（核心功能）

### 设计思路

**参考 LayerZero 的手续费模式**：
```solidity
// 1. 查询手续费
MessagingFee memory fee = oft.quoteSend(sendParam, false);

// 2. 检查用户支付的 native token 是否足够
if (msg.value < fee.nativeFee) revert InsufficientMsgValue();

// 3. 执行跨链操作
oft.send{value: fee.nativeFee}(sendParam, fee, refundAddress);

// 4. 退还多余的 native token
uint256 excess = msg.value - fee.nativeFee;
if (excess > 0) payable(msg.sender).call{value: excess}("");
```

**Circle CCTP 的特点**：
- CCTP 本身不收链上手续费（burn/mint 是免费的）
- 但未来可能需要支付 Relayer 费用
- 我们可以先实现一个简单的手续费机制（即使目前为 0），方便后续扩展

---

## 合约结构

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract CCTPBridgeWrapper is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable 
{
    // Circle 的 TokenMessenger 合约地址
    ITokenMessenger public tokenMessenger;
    
    // USDC 代币地址
    IERC20 public usdc;
    
    // 固定手续费（native token，单位：wei）
    // 初期设为 0，未来可通过 setFee() 调整
    uint256 public bridgeFee;
    
    // 手续费收集地址
    address public feeCollector;

    error InsufficientMsgValue(uint256 required, uint256 provided);
    error NativeRefundFailed();

    event BridgeInitiated(
        uint64 nonce,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint32 destinationDomain
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address oldCollector, address newCollector);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenMessenger,
        address _usdc,
        address _feeCollector,
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        usdc = IERC20(_usdc);
        feeCollector = _feeCollector;
        bridgeFee = 0; // 初期免费
        
        // Max-approve TokenMessenger
        usdc.approve(_tokenMessenger, type(uint256).max);
    }

    /// @notice 一键 USDC 跨链桥接
    /// @param amount USDC 数量（6 decimals）
    /// @param destinationDomain 目标链的 CCTP Domain ID
    /// @param recipient 目标链接收地址
    /// @return nonce Circle 的 nonce，用于追踪交易
    function bridge(
        uint256 amount,
        uint32 destinationDomain,
        address recipient
    ) external payable nonReentrant returns (uint64 nonce) {
        // 1. 检查用户支付的手续费是否足够
        if (msg.value < bridgeFee) {
            revert InsufficientMsgValue(bridgeFee, msg.value);
        }

        // 2. 从用户转入 USDC 到本合约
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "USDC transferFrom failed"
        );

        // 3. 调用 Circle 的 depositForBurn
        bytes32 mintRecipient = _addressToBytes32(recipient);
        nonce = tokenMessenger.depositForBurn(
            amount,
            destinationDomain,
            mintRecipient,
            address(usdc)
        );

        // 4. 收取手续费（如果有）
        if (bridgeFee > 0) {
            (bool feeOk, ) = payable(feeCollector).call{value: bridgeFee}("");
            require(feeOk, "Fee transfer failed");
        }

        // 5. 退还多余的 native token
        uint256 excess = msg.value - bridgeFee;
        if (excess > 0) {
            (bool refundOk, ) = payable(msg.sender).call{value: excess}("");
            if (!refundOk) revert NativeRefundFailed();
        }

        emit BridgeInitiated(nonce, msg.sender, recipient, amount, destinationDomain);
    }

    /// @notice 查询当前手续费
    /// @dev 用户可以先调用这个函数，知道需要传多少 msg.value
    function quoteFee() external view returns (uint256) {
        return bridgeFee;
    }

    /// @notice Owner 更新手续费
    function setFee(uint256 _newFee) external onlyOwner {
        uint256 oldFee = bridgeFee;
        bridgeFee = _newFee;
        emit FeeUpdated(oldFee, _newFee);
    }

    /// @notice Owner 更新手续费收集地址
    function setFeeCollector(address _newCollector) external onlyOwner {
        require(_newCollector != address(0), "Invalid collector");
        address oldCollector = feeCollector;
        feeCollector = _newCollector;
        emit FeeCollectorUpdated(oldCollector, _newCollector);
    }

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

---

## Circle CCTP 接口

```solidity
// src/interfaces/ITokenMessenger.sol
interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce);
}
```

---

## 部署脚本

```solidity
// script/DeployCCTP.s.sol
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CCTPBridgeWrapper} from "../src/CCTPBridgeWrapper.sol";

contract DeployCCTP is Script {
    function run() external {
        address tokenMessenger = vm.envAddress("TOKEN_MESSENGER");
        address usdc = vm.envAddress("USDC");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast();

        // 1. Deploy implementation
        CCTPBridgeWrapper impl = new CCTPBridgeWrapper();

        // 2. Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            CCTPBridgeWrapper.initialize.selector,
            tokenMessenger,
            usdc,
            owner, // feeCollector 初期设为 owner
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        console.log("Implementation:", address(impl));
        console.log("Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
```

---

## 支持的链（Phase 1）

| Chain     | Domain | USDC Address                                 | TokenMessenger Address                       |
|-----------|--------|----------------------------------------------|----------------------------------------------|
| Ethereum  | 0      | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | `0xBd3fa81B58Ba92a82136038B25aDec7066af3155` |
| Arbitrum  | 3      | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | `0x19330d10D9Cc8751218eaf51E8885D058642E08A` |
| Base      | 6      | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | `0x1682Ae6375C4E4A97e4B583BC394c861A46D8962` |

参考：https://developers.circle.com/stablecoins/docs/cctp-technical-reference

---

## 使用示例

### 1. Approve USDC

```bash
cast send $USDC "approve(address,uint256)" $WRAPPER 1000000000 \
  --private-key $PRIVATE_KEY
```

### 2. 查询手续费

```bash
cast call $WRAPPER "quoteFee()" --rpc-url $RPC
```

### 3. 桥接 USDC（Ethereum → Arbitrum）

```bash
AMOUNT="1000000"  # 1 USDC (6 decimals)
DST_DOMAIN=3      # Arbitrum
RECIPIENT=$YOUR_ADDRESS

cast send $WRAPPER \
  "bridge(uint256,uint32,address)" \
  $AMOUNT $DST_DOMAIN $RECIPIENT \
  --value 0 \
  --private-key $PRIVATE_KEY
```

**说明**：
- 初期 `bridgeFee = 0`，所以 `--value 0` 即可
- 如果未来 owner 设置了手续费（例如 0.01 ETH），则需要 `--value 0.01ether`
- 多余的 native token 会自动退还

---

## 测试计划

### 单元测试

```solidity
// test/CCTPBridgeWrapper.t.sol
function testBridge() public {
    // 1. Approve USDC
    usdc.approve(address(wrapper), 1e6);
    
    // 2. Bridge
    uint64 nonce = wrapper.bridge{value: 0}(
        1e6,        // 1 USDC
        3,          // Arbitrum
        recipient
    );
    
    // 3. Verify
    assertGt(nonce, 0);
}

function testFeeRefund() public {
    // 用户多支付了 1 ETH，应该退回
    uint256 balanceBefore = address(this).balance;
    
    wrapper.bridge{value: 1 ether}(1e6, 3, recipient);
    
    uint256 balanceAfter = address(this).balance;
    assertEq(balanceBefore - balanceAfter, 0); // 实际消耗为 0
}
```

---

## 与 LayerZero 版本的对比

| 特性 | LayerZero OFT | Circle CCTP |
|------|---------------|-------------|
| 手续费查询 | `quoteSend()` | `quoteFee()` |
| 手续费支付 | Native token（每次不同） | Native token（固定值，初期 0） |
| 跨链操作 | `send()` | `depositForBurn()` |
| 目标链标识 | `dstEid` (uint32) | `destinationDomain` (uint32) |
| 追踪标识 | `guid` (bytes32) | `nonce` (uint64) |
| 自动退款 | ✅ | ✅ |

---

## 后续扩展（Phase 2+）

如果你需要更多功能，可以后续添加：
- **支持更多链**（Polygon, Optimism 等）
- **批量桥接**
- **链验证** (supportedDomains mapping)
- **Relayer 集成**（自动完成目标链的 mint）

目前先实现 Phase 1，保持简单 ⚪

---

**作者**: Tangyuan  
**日期**: 2026-02-20  
**版本**: v2.0 (Phase 1 focused)
