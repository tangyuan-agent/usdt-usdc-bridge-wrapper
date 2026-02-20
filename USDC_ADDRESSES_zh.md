# USDC 合约地址

> 数据来源: ethskills - 已验证（2026-02-15）

## Circle USDC（原生版本）

| 网络 | 地址 | 状态 |
|------|------|------|
| **Ethereum Mainnet** | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | ✅ 已验证 |
| **Arbitrum** | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | ✅ 已验证 |
| **Optimism** | `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` | ✅ 已验证 |
| **Base** | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | ✅ 已验证 |
| **Polygon** | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` | ✅ 已验证 |
| **zkSync Era** | `0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4` | ✅ 已验证 |

## Circle CCTP 相关信息

### 手续费
- **原生 CCTP**: **0 手续费**（仅支付 gas 费）
- **到账时间**: ~13 分钟（需要等待 Circle Attestation 签名）

### 快速模式（第三方中继）
- **第三方服务**: LayerZero、Chainlink CCIP 等
- **到账时间**: 几乎即时
- **手续费**: 通常 **0.1-1 USDC**

## 测试钱包

**地址**: `0x2E57E3427Ee766108271E9398e1049a4858CbD8f`

⚠️ **私钥存储位置**: `~/.openclaw/workspace/.secrets/tangyuan-wallet.json`  
⚠️ **仅用于测试**，请勿存入大量资金  
⚠️ **重新生成原因**: 避免与 Jason 的 0x69 冷钱包混淆

## 下一步

1. **测试 USDC 批准（approve）**
   - 在测试网（Base Sepolia / Arbitrum Sepolia）上测试
   - 批准 Bridge 合约使用 USDC

2. **测试跨链转账**
   - Base → Arbitrum
   - Arbitrum → Base

3. **验证 CCTP 流程**
   - 发送 burn 交易
   - 获取 attestation
   - 调用 mint 交易
