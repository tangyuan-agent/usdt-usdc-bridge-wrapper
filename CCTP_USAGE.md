# CCTP Bridge Wrapper Usage Guide

## 📦 Contract Overview

**CCTPBridgeWrapper** wraps Circle CCTP protocol's two core functions, providing a clean interface for USDC cross-chain transfers.

### Core Features

- ✅ **Zero Fees** (Phase 1) - Circle CCTP native protocol is completely free
- ✅ **UUPS Upgradeable** - Support for future feature extensions
- ✅ **Two-step Cross-chain** - Source chain send + destination chain receive
- ✅ **Configurable Fees** - Owner can set 0-10% fee (currently 0)

## 🔧 Contract Interface

### 1. Source Chain: `bridgeUSDC()`

Initiate USDC cross-chain transfer on source chain:

```solidity
function bridgeUSDC(
    uint256 amount,           // USDC amount (native decimals, usually 6)
    uint32 destinationDomain, // Destination chain Domain ID
    address recipient         // Recipient address
) external payable returns (uint64 nonce);
```

**Domain IDs**:
- Ethereum: `0`
- Avalanche: `1`
- OP Mainnet: `2`
- Arbitrum: `3`
- Base: `6`
- Polygon: `7`

**Example**:
```solidity
// Polygon → Arbitrum transfer 100 USDC
IERC20(usdc).approve(wrapper, 100e6);
uint64 nonce = wrapper.bridgeUSDC(
    100e6,  // 100 USDC
    3,      // Arbitrum domain
    msg.sender
);
```

### 2. Target Chain: `receiveUSDC()`

Complete USDC mint on destination chain (anyone can call):

```solidity
function receiveUSDC(
    bytes calldata message,     // CCTP message (from source chain event)
    bytes calldata attestation  // Circle attestation
) external returns (bool success);
```

**Example**:
```solidity
// Call after getting attestation from Circle API
bool success = wrapper.receiveUSDC(message, attestation);
```

## 📋 Complete Cross-chain Flow

### Step 1: Source Chain Initiation (e.g. Polygon)

```javascript
// 1. Approve USDC
await usdc.approve(wrapperAddress, amount);

// 2. Call bridgeUSDC
const tx = await wrapper.bridgeUSDC(
    ethers.parseUnits("100", 6), // 100 USDC
    3,                            // Arbitrum
    recipientAddress
);

// 3. Wait for confirmation, get MessageSent event
const receipt = await tx.wait();
const messageSentEvent = receipt.logs.find(/* ... */);
const messageHash = ethers.keccak256(message);
```

### Step 2: Wait for Attestation (~13 minutes)

```bash
# Poll Circle API
curl https://iris-api.circle.com/v1/attestations/{messageHash}

# Wait for status: "complete"
```

### Step 3: Complete on Destination Chain (Arbitrum)

```javascript
// Use received attestation
const tx = await wrapper.receiveUSDC(message, attestation);
await tx.wait();
// ✅ USDC minted to recipient address
```

## 🔑 Owner Functions

### Set Fee

```solidity
// Set 0.5% fee
wrapper.setFee(50); // 50 bps = 0.5%

// Query fee
uint256 fee = wrapper.quoteFee(100e6); // Fee for 100 USDC
```

### Set Fee Recipient

```solidity
wrapper.setFeeRecipient(treasuryAddress);
```

## 🧪 Test Results

### Actual Test (Polygon → Arbitrum)

- **Source Chain TX**: [0xa198aca8bf4d8ec2...](https://polygonscan.com/tx/0xa198aca8bf4d8ec2e2e91669405f5a615253f3be7ff50c078089389b56b35bbc)
- **Destination Chain TX**: [0x2446c399e3b121bd...](https://arbiscan.io/tx/0x2446c399e3b121bda223af71c1ac3a5b2c7b91c4a925dff8816c6a067dc0515d)
- **Amount**: 0.05 USDC
- **Bridge Fee**: 0 USDC (completely free)
- **Gas Fee**: ~$0.001
- **Settlement Time**: <1 minute (fast attestation)

## 📊 Comparison with LayerZero

| Feature | CCTP Wrapper | LayerZero Wrapper |
|---------|--------------|-------------------|
| **Bridge Fee** | 0 (Circle free) | Depends on OFT config |
| **Settlement Time** | ~13 min (standard) | ~1-5 min |
| **Steps** | 2 steps (burn + mint) | 1 step (automatic) |
| **Gas Cost** | Dest chain needs gas | Source chain pays all |
| **Protocol** | Circle official | LayerZero |
| **Security** | Circle backed | LayerZero DVN |

## 🚀 Deployment Guide

### 1. Deploy Script

```solidity
// script/DeployCCTP.s.sol
CCTPBridgeWrapper implementation = new CCTPBridgeWrapper();

bytes memory initData = abi.encodeWithSelector(
    CCTPBridgeWrapper.initialize.selector,
    tokenMessenger,     // Circle TokenMessenger
    messageTransmitter, // Circle MessageTransmitter
    usdc,              // USDC address
    owner
);

ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
```

### 2. Contract Addresses (Per Chain)

Deploy on the following chains:
- Polygon PoS
- Arbitrum One
- Base
- Optimism
- Ethereum Mainnet

Use corresponding Circle CCTP contract addresses for each chain (see `CCTP_CONTRACTS.md`).

## 📝 Important Notes

1. **Two-step Flow** - Unlike LayerZero's one-step completion, CCTP requires users to manually call `receiveUSDC` on destination chain
2. **Attestation Wait** - Standard flow requires ~13 minutes wait (may be faster in practice)
3. **Destination Gas** - Users need ETH on destination chain to pay gas fees
4. **Non-reversible** - Cannot cancel after burn, must complete mint

## 🔮 Future Extensions (Phase 2)

- [ ] Integrate relayer service (automatic mint completion)
- [ ] Gas fee sponsorship (Paymaster mode)
- [ ] USDT → USDC automatic swap
- [ ] Batch cross-chain optimization
- [ ] MEV protection

---

**Contract File**: `src/CCTPBridgeWrapper.sol`  
**Test File**: `test/CCTPBridgeWrapper.t.sol`
