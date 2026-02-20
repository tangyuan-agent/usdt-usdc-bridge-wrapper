# usdt-usdc-bridge-wrapper

One-click cross-chain bridge wrapper for stablecoins.

Currently supported:
- **USDT0** — via LayerZero OFT (`quoteSend` + `send` combined into a single call)

## Setup

```bash
cp .env.example .env
# Fill in your private key, RPC endpoints, and owner address

forge install
forge build
```

## Deploy

```bash
source .env

# Deploy to Polygon
OFT=$OFT_POL forge script script/Deploy.s.sol \
  --rpc-url $RPC_POL --private-key $PK_TEST1 --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API --legacy

# Deploy to Conflux
OFT=$OFT_CFX forge script script/Deploy.s.sol \
  --rpc-url $RPC_CFX --private-key $PK_TEST1 --broadcast --verify \
  --gas-estimate-multiplier 200 \
  --etherscan-api-key $ETHERSCAN_API
```

Save the printed `Proxy` address to `WRAPPER_POL` / `WRAPPER_CFX` in `.env`.

## Upgrade

```bash
source .env

# Upgrade on Polygon
WRAPPER=$WRAPPER_POL forge script script/Upgrade.s.sol \
  --rpc-url $RPC_POL --private-key $PK_TEST1 --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API --legacy

# Upgrade on Conflux
WRAPPER=$WRAPPER_CFX forge script script/Upgrade.s.sol \
  --rpc-url $RPC_CFX --private-key $PK_TEST1 --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API
```

## Usage

### 1. Approve USDT0 spending

```bash
source .env && cast send $USDT_POL \
  "approve(address,uint256)" \
  $WRAPPER_POL 100000000 \
  --private-key $PK_TEST1 \
  --rpc-url $RPC_POL \
  --legacy
```

### 2. Bridge USDT0 (e.g. Polygon -> Arbitrum)

```bash
source .env

AMOUNT="100000"          # 0.1 USDT0 (6 decimals)
DST_EID=$LZID_ARB        # Destination LZ endpoint ID
TO=$OWNER_ADDRESS        # Recipient on destination chain
REFUND=$OWNER_ADDRESS    # Refund address for excess gas

cast send $WRAPPER_POL \
  "bridge(uint256,uint32,address,address)" \
  $AMOUNT $DST_EID $TO $REFUND \
  --value 2ether \
  --private-key $PK_TEST1 \
  --rpc-url $RPC_POL \
  --legacy
```

> `--value` needs to cover the LayerZero messaging fee (native token). Excess is auto-refunded. Use `2 POL` as a safe default, or query `quoteSend` first for the exact fee.

### 3. Track transaction

Check status on [LayerZero Explorer](https://layerzeroscan.com/tx/<tx-hash>).

## Reference

| Chain    | LZ Endpoint ID | USDT0 OFT Address                            | Native USDT Address                          |
|----------|----------------|----------------------------------------------|----------------------------------------------|
| Polygon  | 30109          | `0x6BA10300f0DC58B7a1e4c0e41f5daBb7D7829e13` | `0xc2132D05D31c914a87C6611C10748AEb04B58e8F` |
| Arbitrum | 30110          | `0x14E4A1B13bf7F943c8ff7C51fb60FA964A298D92` | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` |
| Conflux  | 30212          | `0xC57efa1c7113D98BdA6F9f249471704Ece5dd84A` | `0xaf37E8B6C9ED7f6318979f56Fc287d76c30847ff` |

Full list: https://docs.usdt0.to/api/deployments
