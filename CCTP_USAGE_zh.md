# CCTP Bridge Wrapper 使用指南

## 📦 合约概述

**CCTPBridgeWrapper** 封装了 Circle CCTP 协议的两个核心函数，提供简洁的 USDC 跨链接口。

### 核心特性

- ✅ **零手续费**（Phase 1）- Circle CCTP 原生完全免费
- ✅ **UUPS 可升级** - 支持未来功能扩展
- ✅ **两步式跨链** - 源链发送 + 目标链接收
- ✅ **手续费可配置** - Owner 可设置 0-10% 手续费（当前为 0）

## 🔧 合约接口

### 1. Source Chain: `bridgeUSDC()`

在源链发起 USDC 跨链转账：

```solidity
function bridgeUSDC(
    uint256 amount,           // USDC 数量（原生精度，通常 6 位）
    uint32 destinationDomain, // 目标链 Domain ID
    address recipient         // 接收地址
) external payable returns (uint64 nonce);
```

**Domain IDs**:
- Ethereum: `0`
- Avalanche: `1`
- OP Mainnet: `2`
- Arbitrum: `3`
- Base: `6`
- Polygon: `7`

**示例**:
```solidity
// Polygon → Arbitrum 转账 100 USDC
IERC20(usdc).approve(wrapper, 100e6);
uint64 nonce = wrapper.bridgeUSDC(
    100e6,  // 100 USDC
    3,      // Arbitrum domain
    msg.sender
);
```

### 2. Target Chain: `receiveUSDC()`

在目标链完成 USDC mint（任何人都可调用）：

```solidity
function receiveUSDC(
    bytes calldata message,     // CCTP message（从源链事件获取）
    bytes calldata attestation  // Circle attestation
) external returns (bool success);
```

**示例**:
```solidity
// 从 Circle API 获取 attestation 后调用
bool success = wrapper.receiveUSDC(message, attestation);
```

## 📋 完整跨链流程

### Step 1: 源链发起（例如 Polygon）

```javascript
// 1. Approve USDC
await usdc.approve(wrapperAddress, amount);

// 2. 调用 bridgeUSDC
const tx = await wrapper.bridgeUSDC(
    ethers.parseUnits("100", 6), // 100 USDC
    3,                            // Arbitrum
    recipientAddress
);

// 3. 等待交易确认，获取 MessageSent 事件
const receipt = await tx.wait();
const messageSentEvent = receipt.logs.find(/* ... */);
const messageHash = ethers.keccak256(message);
```

### Step 2: 等待 Attestation（~13 分钟）

```bash
# 轮询 Circle API
curl https://iris-api.circle.com/v1/attestations/{messageHash}

# 等待返回 status: "complete"
```

### Step 3: 目标链完成（Arbitrum）

```javascript
// 使用获取到的 attestation
const tx = await wrapper.receiveUSDC(message, attestation);
await tx.wait();
// ✅ USDC 已 mint 到 recipient 地址
```

## 🔑 Owner 功能

### 设置手续费

```solidity
// 设置 0.5% 手续费
wrapper.setFee(50); // 50 bps = 0.5%

// 查询手续费
uint256 fee = wrapper.quoteFee(100e6); // 100 USDC 的手续费
```

### 设置手续费接收地址

```solidity
wrapper.setFeeRecipient(treasuryAddress);
```

## 🧪 测试结果

### 实际测试（Polygon → Arbitrum）

- **源链交易**: [0xa198aca8bf4d8ec2...](https://polygonscan.com/tx/0xa198aca8bf4d8ec2e2e91669405f5a615253f3be7ff50c078089389b56b35bbc)
- **目标链交易**: [0x2446c399e3b121bd...](https://arbiscan.io/tx/0x2446c399e3b121bda223af71c1ac3a5b2c7b91c4a925dff8816c6a067dc0515d)
- **金额**: 0.05 USDC
- **手续费**: 0 USDC（完全免费）
- **Gas 费**: ~$0.001
- **到账时间**: <1 分钟（attestation 速度快）

## 📊 与 LayerZero 方案对比

| 特性 | CCTP Wrapper | LayerZero Wrapper |
|------|--------------|-------------------|
| **手续费** | 0（Circle 免费） | 依赖 OFT 配置 |
| **到账时间** | ~13 分钟（标准）| ~1-5 分钟 |
| **步骤** | 2 步（burn + mint）| 1 步（自动） |
| **Gas 成本** | 目标链需 gas | 源链支付全部 |
| **协议** | Circle 官方 | LayerZero |
| **安全性** | Circle 背书 | LayerZero DVN |

## 🚀 部署指南

### 1. 部署脚本

```solidity
// script/DeployCCTP.s.sol
CCTPBridgeWrapper implementation = new CCTPBridgeWrapper();

bytes memory initData = abi.encodeWithSelector(
    CCTPBridgeWrapper.initialize.selector,
    tokenMessenger,  // Circle TokenMessenger
    messageTransmitter, // Circle MessageTransmitter
    usdc,           // USDC address
    owner
);

ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
```

### 2. 合约地址（每条链）

需要在以下链上部署：
- Polygon PoS
- Arbitrum One
- Base
- Optimism
- Ethereum Mainnet

每条链使用对应的 Circle CCTP 合约地址（见 `CCTP_CONTRACTS.md`）。

## 📝 注意事项

1. **两步式流程** - 不同于 LayerZero 的一步完成，CCTP 需要用户在目标链手动调用 `receiveUSDC`
2. **Attestation 等待** - 标准流程需等待 ~13 分钟（实际可能更快）
3. **目标链 Gas** - 用户需在目标链有 ETH 支付 gas 费
4. **无法撤销** - Burn 后无法取消，必须完成 mint

## 🔮 未来扩展（Phase 2）

- [ ] 集成中继服务（自动完成 mint）
- [ ] Gas 费代付（Paymaster 模式）
- [ ] USDT → USDC 自动兑换
- [ ] 批量跨链优化
- [ ] MEV 保护

---

**合约文件**: `src/CCTPBridgeWrapper.sol`  
**测试文件**: `test/CCTPBridgeWrapper.t.sol`
