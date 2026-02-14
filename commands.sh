# https://docs.usdt0.to/api/deployments to see LZIDs & addresses

ADDR="0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
ADDR_32="0x000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
OFT_POL="0x6BA10300f0DC58B7a1e4c0e41f5daBb7D7829e13"

EXTRA_OPTIONS="0x0003"
LZID_ARB="30110"
AMOUNT_IN="200000"
AMOUNT_OUT_MIN="190000"

# Struct Definitions (for reference):
# SendParam:
#   - dstEid (uint32): Destination endpoint ID.
#   - to (bytes32): Recipient address.
#   - amountLD (uint256): Amount to send in local decimals.
#   - minAmountLD (uint256): Minimum amount to send in local decimals.
#   - extraOptions (bytes): Additional options supplied by the caller (e.g. for gas).
#   - composeMsg (bytes): The composed message for the send() operation.
#   - oftCmd (bytes): The OFT command to be executed.

# IOFT: https://github.com/LayerZero-Labs/devtools/blob/main/packages/oft-evm/contracts/interfaces/IOFT.sol
# OFTCore: https://github.com/LayerZero-Labs/devtools/blob/main/packages/oft-evm/contracts/OFTCore.sol

# -----------------------------------------------------------------------------
# Function: quoteOFT
# Description: Estimates the OFT fee details and receipt information.
# Input:
#   - _sendParam (SendParam): The parameters for the send operation.
# Output (tuple):
#   - oftLimit (OFTLimit):
#       - minAmountLD (uint256): Min amount in local decimals that can be sent.
#       - maxAmountLD (uint256): Max amount in local decimals that can be sent.
#   - oftFeeDetails (OFTFeeDetail[]):
#       - feeAmountLD (int256): Amount of the fee in local decimals.
#       - description (string): Description of the fee.
#   - oftReceipt (OFTReceipt):
#       - amountSentLD (uint256): Amount actually debited from sender.
#       - amountReceivedLD (uint256): Amount to be received on remote side.
# -----------------------------------------------------------------------------
cast call $OFT_POL \
  "quoteOFT((uint32,bytes32,uint256,uint256,bytes,bytes,bytes))((uint256,uint256),(int256,string)[],(uint256,uint256))" \
  "($LZID_ARB,$ADDR_32,$AMOUNT_IN,$AMOUNT_OUT_MIN,$EXTRA_OPTIONS,0x,0x)" \
  --rpc-url $RPC_POL

# -----------------------------------------------------------------------------
# Function: quoteSend
# Description: Estimates the LayerZero messaging fee.
# Input:
#   - _sendParam (SendParam): The parameters for the send operation.
#   - _payInLzToken (bool): Whether to pay the fee in LZ tokens.
# Output (MessagingFee):
#   - nativeFee (uint256): The fee in native gas token.
#   - lzTokenFee (uint256): The fee in LZ token.
# -----------------------------------------------------------------------------
RESULT=$(cast call $OFT_POL \
  "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)(uint256,uint256)" \
  "($LZID_ARB,$ADDR_32,$AMOUNT_IN,$AMOUNT_OUT_MIN,$EXTRA_OPTIONS,0x,0x)" \
  false \
  --rpc-url $RPC_POL)

NATIVE_FEE=$(echo "$RESULT" | head -n 1 | tr -d '()' | awk -F',' '{print $1}' | awk '{print $1}')
echo "Native Fee: $NATIVE_FEE wei"
echo "Native Fee in POL: $(cast --from-wei $NATIVE_FEE)"

# -----------------------------------------------------------------------------
# Function: send
# Description: Executes the cross-chain transfer.
# Input:
#   - _sendParam (SendParam): The parameters for the send operation.
#   - _fee (MessagingFee): The fee information (nativeFee, lzTokenFee).
#   - _refundAddress (address): Address to receive any excess funds/gas.
# Output (tuple):
#   - msgReceipt (MessagingReceipt):
#       - guid (bytes32): Unique identifier for the message.
#       - nonce (uint64): Message nonce.
#       - fee (MessagingFee): The fee paid.
#   - oftReceipt (OFTReceipt):
#       - amountSentLD (uint256): Amount actually debited.
#       - amountReceivedLD (uint256): Amount to be received.
# -----------------------------------------------------------------------------
cast send $OFT_POL \
  "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)" \
  "($LZID_ARB,$ADDR_32,$AMOUNT_IN,$AMOUNT_OUT_MIN,$EXTRA_OPTIONS,0x,0x)" \
  "($NATIVE_FEE,0)" \
  "$ADDR" \
  --value $NATIVE_FEE \
  --private-key $PK_TEST1 \
  --rpc-url $RPC_POL \
  --legacy

# After that:
#  Check in Layerzero explorer (https://layerzeroscan.com/tx/<tx-hash>)