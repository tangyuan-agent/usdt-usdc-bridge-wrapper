# CCTP Relayer - DIY Auto-Mint Service

## What is This?

A self-hosted relayer service that automatically completes USDC cross-chain transfers by:

1. **Monitoring** MessageSent events on source chain
2. **Fetching** attestation from Circle API
3. **Executing** receiveMessage on destination chain

**Result**: Users don't need to manually mint on destination chain - the relayer does it automatically.

## Why Build Your Own Relayer?

| Feature | DIY Relayer | Third-party Service |
|---------|-------------|---------------------|
| **Cost** | Only gas fees (~$0.001) | $0.10-1.00 per tx |
| **Control** | Full control | Depends on service |
| **Privacy** | No data sharing | Shares tx data |
| **Customization** | Fully customizable | Limited |

## Setup

### 1. Install Dependencies

```bash
cd /root/.openclaw/workspace/usdt-usdc-bridge-wrapper
npm install ethers@6
```

### 2. Configure Wallet

The relayer uses your wallet to pay gas fees on the destination chain. Make sure you have:

- **Arbitrum ETH**: ~0.001 ETH for gas (to complete mints)

Current wallet: `0x2E57E3427Ee766108271E9398e1049a4858CbD8f`

## Usage

### Mode 1: Watch Mode (Continuous)

Monitor for new cross-chain transfers and auto-complete them:

```bash
node relayer/cctp-relayer.mjs --watch
```

**Output:**
```
🚀 CCTP Relayer Started
=====================================
Source: Polygon
Destination: Arbitrum
Relayer: 0x2E57E3427Ee766108271E9398e1049a4858CbD8f
=====================================

📍 Starting from block: 83229846

🔍 Scanning blocks...
   Found 1 message(s)

📨 Processing message: 0x648d0b...
   🔄 Fetching attestation from Circle...
   ✅ Attestation received
   🎁 Calling receiveMessage on Arbitrum...
   ✅ Mint completed! Block: 434044249
```

### Mode 2: Process Specific Transaction

Manually trigger mint for a specific burn transaction:

```bash
node relayer/cctp-relayer.mjs --tx 0xa198aca8bf4d8ec2e2e91669405f5a615253f3be7ff50c078089389b56b35bbc
```

## Configuration

Edit `cctp-relayer.mjs` to customize:

```javascript
const CONFIG = {
  // Source chain
  source: {
    rpc: 'https://polygon-bor-rpc.publicnode.com',
    tokenMessenger: '0x9daF8c91AEFAE50b9c0E69629D3F6Ca40cA3B3FE',
    chainName: 'Polygon'
  },
  
  // Destination chain  
  destination: {
    rpc: 'https://arb1.arbitrum.io/rpc',
    messageTransmitter: '0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca',
    chainName: 'Arbitrum'
  },
  
  // Polling interval (seconds)
  pollInterval: 60,
  
  // Attestation retry settings
  attestationRetries: 20,
  attestationRetryInterval: 30000 // 30 seconds
};
```

## How It Works

### Flow Diagram

```
User                    Relayer                Circle              Blockchain
  |                        |                       |                    |
  |-- depositForBurn -->   |                       |                    |
  |                        |                       |                    |
  |                        |<-- Monitor events --> |                    |
  |                        |                       |                    |
  |                        |-- Get attestation --> |                    |
  |                        |<-- Attestation -----  |                    |
  |                        |                       |                    |
  |                        |-- receiveMessage ---> |                    |
  |                        |                       |                    |
  |<---------------------- USDC minted -----------|<-------------------|
```

### Step-by-Step

1. **User burns USDC** on source chain (Polygon)
2. **MessageSent event** is emitted with message payload
3. **Relayer detects** the event
4. **Relayer polls** Circle API for attestation (~13 min)
5. **Relayer calls** `receiveMessage()` on destination chain (Arbitrum)
6. **USDC is minted** to user's address on Arbitrum

## Cost Analysis

### Per Transaction

- **Third-party Relayer**: $0.10-1.00
- **DIY Relayer**: ~$0.001 (only gas)

### Monthly Savings (100 tx/month)

- **Third-party**: $10-100/month
- **DIY**: ~$0.10/month
- **Savings**: **$9.90-99.90/month** 💰

## Production Deployment

### Run as Service (systemd)

Create `/etc/systemd/system/cctp-relayer.service`:

```ini
[Unit]
Description=CCTP Relayer Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/.openclaw/workspace/usdt-usdc-bridge-wrapper
ExecStart=/usr/bin/node relayer/cctp-relayer.mjs --watch
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable cctp-relayer
sudo systemctl start cctp-relayer
sudo systemctl status cctp-relayer
```

### Monitor Logs

```bash
journalctl -u cctp-relayer -f
```

## Multi-Chain Support

To support multiple routes (e.g., Polygon→Arbitrum, Base→Optimism):

1. **Create config file** for each route
2. **Run multiple instances** with different configs
3. **Or modify** the relayer to monitor multiple chains

## Security Notes

⚠️ **Important:**

- The relayer wallet pays gas fees - keep sufficient ETH
- Private key is stored in `/root/.openclaw/workspace/.secrets/tangyuan-wallet.json`
- For production, use dedicated relayer wallet (not personal)
- Consider using hardware wallet or KMS for key management

## Troubleshooting

### "Insufficient funds for gas"

Add more ETH to the relayer wallet on the destination chain.

### "Attestation timeout"

Increase `attestationRetries` or `attestationRetryInterval` in config.

### "Message already received"

The message was already processed. Check Arbiscan to verify.

## Advanced Features (Future)

- [ ] Multi-chain routing (more than 2 chains)
- [ ] Fee estimation before processing
- [ ] Notification system (Telegram/Discord)
- [ ] Dashboard UI
- [ ] MEV protection
- [ ] Gas price optimization
- [ ] Batch processing

---

**File**: `relayer/cctp-relayer.mjs`  
**Status**: Production-ready ✅  
**Tested**: Polygon → Arbitrum  
**Cost**: ~$0.001 per transaction
