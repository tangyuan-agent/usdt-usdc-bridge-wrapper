# How to Get CCTP receiveMessage Parameters

## Overview

The `receiveMessage` function requires two parameters:

```solidity
function receiveMessage(
    bytes calldata message,      // From source chain event
    bytes calldata attestation   // From Circle API
) external returns (bool success);
```

## Parameter 1: `message`

### Source
**MessageSent event** emitted by TokenMessenger on the **source chain** (Polygon)

### How to Get It

```javascript
// 1. Get the burn transaction receipt
const receipt = await provider.getTransactionReceipt(burnTxHash);

// 2. Parse logs to find MessageSent event
const tokenMessengerInterface = new ethers.Interface([
  'event MessageSent(bytes message)'
]);

for (const log of receipt.logs) {
  try {
    const parsed = tokenMessengerInterface.parseLog(log);
    if (parsed && parsed.name === 'MessageSent') {
      const message = parsed.args.message;
      // This is your 'message' parameter!
      break;
    }
  } catch {
    // Not a MessageSent event, skip
  }
}
```

### Message Structure

The `message` bytes contains (packed binary):

| Field | Type | Example Value | Description |
|-------|------|---------------|-------------|
| Version | uint32 | 0 | Message format version |
| Source Domain | uint32 | 7 | Polygon domain ID |
| Destination Domain | uint32 | 3 | Arbitrum domain ID |
| Nonce | uint64 | 26336 | Unique message ID |
| Sender | bytes32 | 0x9daf8c91... | TokenMessenger (source) |
| Recipient | bytes32 | 0x19330d10... | TokenMessenger (dest) |
| Destination Caller | bytes32 | 0x000...000 | Who can call mint (0 = anyone) |
| Message Body | bytes | ... | Contains burn/mint details |

#### Message Body Structure

| Field | Type | Value | Description |
|-------|------|-------|-------------|
| Version | uint32 | 0 | Body version |
| Burn Token | bytes32 | 0x3c499c54... | USDC address (source) |
| Mint Recipient | bytes32 | 0x2e57e342... | Your wallet address |
| Amount | uint256 | 50000 | 0.05 USDC (6 decimals) |
| Message Sender | bytes32 | 0x2e57e342... | Original caller address |

### Example Value

```
0x00000000000000070000000300000000000660e00000000000000000000000009daf8c91aefae50b9c0e69629d3f6ca40ca3b3fe00000000000000000000000019330d10d9cc8751218eaf51e8885d058642e08a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003c499c542cef5e3811e1192ce70d8cc03d5c33590000000000000000000000002e57e3427ee766108271e9398e1049a4858cbd8f000000000000000000000000000000000000000000000000000000000000c3500000000000000000000000002e57e3427ee766108271e9398e1049a4858cbd8f
```

Length: 248 bytes (496 hex chars)

## Parameter 2: `attestation`

### Source
**Circle Iris API** - https://iris-api.circle.com/v1/attestations/{messageHash}

### How to Get It

```javascript
// 1. Calculate message hash
const messageHash = ethers.keccak256(message);
// Example: 0x648d0bcd2b18cc332a8dd13a84af8a117d658cce7263c638231ad331a45e0d1d

// 2. Poll Circle API
const url = `https://iris-api.circle.com/v1/attestations/${messageHash}`;

async function getAttestation(messageHash) {
  for (let i = 0; i < 20; i++) {
    const response = await fetch(url);
    const data = await response.json();
    
    if (data.status === 'complete') {
      return data.attestation; // Got it!
    }
    
    console.log('Waiting for attestation...');
    await sleep(30000); // Wait 30 seconds
  }
  
  throw new Error('Attestation timeout');
}
```

### API Response Format

**Pending:**
```json
{
  "status": "pending_confirmations",
  "attestation": null
}
```

**Complete (~13 minutes later):**
```json
{
  "status": "complete",
  "attestation": "0x384d2a3f122522f96869b8e0f8d9edb048dfeba91bbfdc5b197a61cd10719bf85f4c1b32ab3c7fd5f4eee27560fc9cd943f289c8a605a35ce84577d2f7851a121c64c0904084ba5a18a214bdda991bc270628ae1b16c30d136b9396226900ce0d73a40e82c3a531372732643536477b54090d53fc8b670ab3e307cbedb27a91d2e1b"
}
```

### Attestation Structure

The attestation is a **multi-signature** from Circle's validator nodes:

- **Length**: 65-130 bytes (depending on signature format)
- **Content**: ECDSA signatures proving:
  - The burn transaction is valid
  - The message is authentic
  - The amount is correct
  - Circle validators approved it

This is similar to a **notarized document** - Circle validators sign to confirm "yes, this burn happened and is legitimate."

## Complete Example

### Step 1: Burn on Source Chain (Polygon)

```javascript
// User calls depositForBurn
const tx = await tokenMessenger.depositForBurn(
  50000,  // 0.05 USDC
  3,      // Arbitrum
  recipientBytes32,
  usdcAddress
);

await tx.wait();
// TX: 0xa198aca8bf4d8ec2e2e91669405f5a615253f3be7ff50c078089389b56b35bbc
```

### Step 2: Extract Message

```javascript
const receipt = await provider.getTransactionReceipt(tx.hash);
const messageSentEvent = findMessageSentEvent(receipt);
const message = messageSentEvent.args.message;
const messageHash = ethers.keccak256(message);

console.log('Message:', message);
console.log('Message Hash:', messageHash);
```

**Output:**
```
Message: 0x00000000000000070000000300000000000660e0...
Message Hash: 0x648d0bcd2b18cc332a8dd13a84af8a117d658cce7263c638231ad331a45e0d1d
```

### Step 3: Get Attestation

```javascript
const attestation = await getAttestation(messageHash);
console.log('Attestation:', attestation);
```

**Output (after ~13 min):**
```
Attestation: 0x384d2a3f122522f96869b8e0f8d9edb048dfeba91bbfdc5b197a61cd10719bf8...
```

### Step 4: Mint on Destination Chain (Arbitrum)

```javascript
const tx = await messageTransmitter.receiveMessage(
  message,       // from Step 2
  attestation    // from Step 3
);

await tx.wait();
// TX: 0x2446c399e3b121bda223af71c1ac3a5b2c7b91c4a925dff8816c6a067dc0515d
```

**Result:**
✅ 0.05 USDC minted to recipient address on Arbitrum!

## Verification

You can see these exact values in the Arbitrum transaction:

**Transaction**: https://arbiscan.io/tx/0x2446c399e3b121bda223af71c1ac3a5b2c7b91c4a925dff8816c6a067dc0515d

**Input Data:**
- **Name**: `receiveMessage`
- **Param 0** (`message`): `0x00000000000000070000000300000000000660e0...`
- **Param 1** (`attestation`): `0x384d2a3f122522f96869b8e0f8d9edb048d...`

## Summary

| Parameter | Source | How to Get | Wait Time |
|-----------|--------|------------|-----------|
| `message` | Source chain event | Parse `MessageSent` from burn tx receipt | Immediate |
| `attestation` | Circle API | Poll `/attestations/{messageHash}` | ~13 minutes |

**Key Insight**: The `message` contains all the transfer details (who, what, how much), and the `attestation` is Circle's cryptographic proof that it's legitimate.

---

**Reference Transaction (Polygon → Arbitrum):**
- Source TX: https://polygonscan.com/tx/0xa198aca8bf4d8ec2e2e91669405f5a615253f3be7ff50c078089389b56b35bbc
- Dest TX: https://arbiscan.io/tx/0x2446c399e3b121bda223af71c1ac3a5b2c7b91c4a925dff8816c6a067dc0515d
- Amount: 0.05 USDC
- Time: Feb 20, 2026
