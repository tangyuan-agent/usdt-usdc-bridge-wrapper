// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IOFT, SendParam, MessagingFee, MessagingReceipt} from "./interfaces/IOFT.sol";

/// @title L0Transfer - One-click LayerZero OFT cross-chain transfer
/// @notice Wraps quoteSend + send into a single call
contract L0Transfer {
    IOFT public immutable oft;

    // Default extra options (OptionsType V3, no extra config)
    bytes constant DEFAULT_EXTRA_OPTIONS = hex"0003";
    // Default slippage: 5%
    uint256 constant SLIPPAGE_BPS = 500;
    uint256 constant BPS_DENOMINATOR = 10000;

    error InsufficientMsgValue(uint256 required, uint256 provided);
    error NativeRefundFailed();

    constructor(address _oft) {
        oft = IOFT(_oft);
    }

    /// @notice One-click cross-chain OFT transfer
    /// @param amount Amount of tokens to send (in local decimals, e.g. 6 for USDT0)
    /// @param dstEid Destination LayerZero endpoint ID (e.g. 30110 for Arbitrum)
    /// @param to Recipient address on the destination chain
    /// @param refundAddress Address to receive excess native gas refund
    /// @return guid The unique message identifier for tracking on LayerZero explorer
    function transfer(
        uint256 amount,
        uint32 dstEid,
        address to,
        address refundAddress
    ) external payable returns (bytes32 guid) {
        // Build SendParam with defaults
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: _addressToBytes32(to),
            amountLD: amount,
            minAmountLD: amount * (BPS_DENOMINATOR - SLIPPAGE_BPS) / BPS_DENOMINATOR,
            extraOptions: DEFAULT_EXTRA_OPTIONS,
            composeMsg: "",
            oftCmd: ""
        });

        // Step 1: quoteSend - get the native fee required
        MessagingFee memory fee = oft.quoteSend(sendParam, false);

        if (msg.value < fee.nativeFee) {
            revert InsufficientMsgValue(fee.nativeFee, msg.value);
        }

        // Step 2: Pull OFT tokens from sender
        require(
            IERC20(address(oft)).transferFrom(msg.sender, address(this), amount),
            "transferFrom failed"
        );

        // Step 3: send - execute the cross-chain transfer
        (MessagingReceipt memory receipt, ) = oft.send{value: fee.nativeFee}(
            sendParam,
            fee,
            refundAddress
        );

        // Refund excess native token
        uint256 excess = msg.value - fee.nativeFee;
        if (excess > 0) {
            (bool ok, ) = payable(msg.sender).call{value: excess}("");
            if (!ok) revert NativeRefundFailed();
        }

        return receipt.guid;
    }

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
