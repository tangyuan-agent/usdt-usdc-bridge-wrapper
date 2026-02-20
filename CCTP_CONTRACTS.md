# Circle CCTP 合约地址

> ⚠️ **重要**: 这些是 Circle CCTP 的核心合约地址，在测试前需要验证  
> 数据来源：Circle 官方文档 + ethskills

## 核心概念

### CCTP 核心合约

1. **TokenMessenger** - 用户入口合约
   - `depositForBurn()` - 发起 burn，开始跨链转账
   
2. **MessageTransmitter** - 消息传输合约
   - `receiveMessage()` - 接收 attestation，完成 mint

3. **TokenMinter** - USDC 铸造/销毁合约
   - 由 TokenMessenger 调用

## Domain IDs（链标识符）

| 链 | Domain ID |
|-----|----------|
| Ethereum | 0 |
| Avalanche | 1 |
| OP Mainnet | 2 |
| Arbitrum | 3 |
| **Polygon** | **7** |
| **Base** | **6** |
| Solana | 5 |

## 关键合约地址（需要验证）

### Ethereum Mainnet
```
TokenMessenger: 0xbd3fa81b58ba92a82136038b25adec7066af3155
MessageTransmitter: 0x0a992d191DEeC32aFe36203Ad87D7d289a738F81
USDC: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
```

### Arbitrum One
```
TokenMessenger: 0x19330d10D9Cc8751218eaf51E8885D058642E08A
MessageTransmitter: 0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca
USDC: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
```

### Polygon PoS
```
TokenMessenger: 0x9daF8c91AEFAE50b9c0E69629D3F6Ca40cA3B3FE
MessageTransmitter: 0xF3be9355363857F3e001be68856A2f96b4C39Ba9
USDC: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
```

### Base
```
TokenMessenger: 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962
MessageTransmitter: 0xAD09780d193884d503182aD4588450C416D6F9D4
USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
```

### Optimism (OP Mainnet)
```
TokenMessenger: 0x2B4069517957735bE00ceE0fadAE88a26365528f
MessageTransmitter: 0x4D41f22c5a0e5c74090899E5a8Fb597a8842b3e8
USDC: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85
```

## 使用流程

### 1. 发起跨链转账（Source Chain）

```solidity
// 1. Approve USDC to TokenMessenger
IERC20(usdc).approve(tokenMessenger, amount);

// 2. Call depositForBurn
uint64 nonce = ITokenMessenger(tokenMessenger).depositForBurn(
    amount,           // amount
    destinationDomain, // 目标链 domain ID
    mintRecipient,    // bytes32(uint256(uint160(recipient)))
    usdc              // USDC address
);
```

### 2. 获取 Attestation

```bash
# Circle Attestation API
curl "https://iris-api.circle.com/attestations/{messageHash}"
```

### 3. 完成转账（Destination Chain）

```solidity
// 使用 attestation 调用 receiveMessage
IMessageTransmitter(messageTransmitter).receiveMessage(
    message,      // 从事件中获取
    attestation   // 从 Circle API 获取
);
```

## 手续费

- **Standard Transfer**: **0 onchain fee** ✨
- **到账时间**: ~13 分钟（等待 finality + attestation）
- **Gas 费**: 需要支付（Ethereum: ~$0.01，L2s: ~$0.001）

## 公共 RPC 端点

| 链 | RPC URL | 状态 |
|----|---------|------|
| Polygon | `https://polygon-bor-rpc.publicnode.com` | ✅ 可用 |
| Arbitrum | `https://arb1.arbitrum.io/rpc` | 待验证 |
| Base | `https://mainnet.base.org` | 待验证 |

## 当前余额（2026-02-20）

**钱包地址**: `0x2E57E3427Ee766108271E9398e1049a4858CbD8f`

### Polygon
- ✅ **POL**: 3.00003 POL
- ✅ **USDC**: 0.1 USDC

## 测试计划

1. ✅ 准备测试钱包（已完成）
2. ✅ 收到测试代币（Polygon: 3 POL + 0.1 USDC）
3. 🔲 验证 CCTP 合约地址
4. 🔲 测试 Polygon → Arbitrum USDC 跨链
5. 🔲 测试 Arbitrum → Polygon USDC 跨链
