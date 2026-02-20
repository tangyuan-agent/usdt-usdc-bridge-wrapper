# USDC Contract Addresses

> Source: ethskills - Verified (2026-02-15)

## Circle USDC (Native)

| Network | Address | Status |
|---------|---------|--------|
| **Ethereum Mainnet** | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | ✅ Verified |
| **Arbitrum** | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | ✅ Verified |
| **Optimism** | `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` | ✅ Verified |
| **Base** | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | ✅ Verified |
| **Polygon** | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` | ✅ Verified |
| **zkSync Era** | `0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4` | ✅ Verified |

## Circle CCTP Information

### Fees
- **Native CCTP**: **0 fees** (only gas fees)
- **Settlement Time**: ~13 minutes (waiting for Circle Attestation signature)

### Fast Mode (Third-party Relayers)
- **Third-party Services**: LayerZero, Chainlink CCIP, etc.
- **Settlement Time**: Near instant
- **Fees**: Typically **0.1-1 USDC**

## Test Wallet

**Address**: `0x2E57E3427Ee766108271E9398e1049a4858CbD8f`

⚠️ **Private Key Location**: `~/.openclaw/workspace/.secrets/tangyuan-wallet.json`  
⚠️ **For testing only**, do not deposit large amounts

## Next Steps

1. **Test USDC approve**
   - Test on testnets (Base Sepolia / Arbitrum Sepolia)
   - Approve Bridge contract to use USDC

2. **Test cross-chain transfers**
   - Base → Arbitrum
   - Arbitrum → Base

3. **Verify CCTP flow**
   - Send burn transaction
   - Get attestation
   - Call mint transaction
