// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title CCTPBridgeWrapper - Circle CCTP cross-chain USDC bridge (UUPS upgradeable)
/// @notice Wraps Circle's burn-and-mint CCTP protocol for seamless cross-chain USDC transfers
/// @dev Phase 1: Native CCTP only (0 bridge fee, ~13 min settlement)
interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce);
}

interface IMessageTransmitter {
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool success);
}

contract CCTPBridgeWrapper is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Circle TokenMessenger contract (source chain)
    ITokenMessenger public tokenMessenger;
    
    /// @notice Circle MessageTransmitter contract (destination chain)
    IMessageTransmitter public messageTransmitter;
    
    /// @notice USDC token contract
    IERC20 public usdc;
    
    /// @notice Bridge fee in basis points (0 = free in Phase 1)
    uint256 public bridgeFee;
    
    /// @notice Fee recipient address
    address public feeRecipient;
    
    /// @notice Maximum bridge fee cap (10% = 1000 bps)
    uint256 constant MAX_FEE_BPS = 1000;
    uint256 constant BPS_DENOMINATOR = 10000;

    event BridgeInitiated(
        address indexed sender,
        uint256 amount,
        uint32 destinationDomain,
        address indexed recipient,
        uint64 nonce
    );
    
    event BridgeCompleted(
        address indexed recipient,
        uint256 amount,
        bytes32 messageHash
    );
    
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    error InvalidFee(uint256 fee);
    error ZeroAddress();
    error InsufficientAmount(uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract (UUPS pattern)
    /// @param _tokenMessenger Circle TokenMessenger address
    /// @param _messageTransmitter Circle MessageTransmitter address
    /// @param _usdc USDC token address
    /// @param _owner Contract owner
    function initialize(
        address _tokenMessenger,
        address _messageTransmitter,
        address _usdc,
        address _owner
    ) external initializer {
        if (_tokenMessenger == address(0) || _messageTransmitter == address(0) 
            || _usdc == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }

        __Ownable_init(_owner);
        
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        messageTransmitter = IMessageTransmitter(_messageTransmitter);
        usdc = IERC20(_usdc);
        
        // Phase 1: Free bridging (0 fee)
        bridgeFee = 0;
        feeRecipient = _owner;
        
        // Max-approve TokenMessenger to pull USDC
        usdc.approve(_tokenMessenger, type(uint256).max);
    }

    /// @notice Bridge USDC to another chain (source chain function)
    /// @param amount Amount of USDC to bridge (in native decimals, e.g. 6 for USDC)
    /// @param destinationDomain Circle CCTP destination domain ID
    ///        Ethereum = 0, Avalanche = 1, OP = 2, Arbitrum = 3, Base = 6, Polygon = 7
    /// @param recipient Recipient address on destination chain
    /// @return nonce CCTP message nonce for tracking
    function bridgeUSDC(
        uint256 amount,
        uint32 destinationDomain,
        address recipient
    ) external payable returns (uint64 nonce) {
        if (amount == 0) revert InsufficientAmount(amount);
        if (recipient == address(0)) revert ZeroAddress();

        // Calculate fee (currently 0 in Phase 1)
        uint256 feeAmount = (amount * bridgeFee) / BPS_DENOMINATOR;
        uint256 bridgeAmount = amount - feeAmount;

        // Pull USDC from sender
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "transferFrom failed"
        );

        // Collect fee if non-zero
        if (feeAmount > 0) {
            require(
                usdc.transfer(feeRecipient, feeAmount),
                "fee transfer failed"
            );
        }

        // Convert recipient to bytes32 (CCTP format)
        bytes32 mintRecipient = bytes32(uint256(uint160(recipient)));

        // Execute Circle CCTP burn
        nonce = tokenMessenger.depositForBurn(
            bridgeAmount,
            destinationDomain,
            mintRecipient,
            address(usdc)
        );

        // Refund excess native token if any (for future gas sponsorship)
        if (msg.value > 0) {
            (bool success, ) = payable(msg.sender).call{value: msg.value}("");
            require(success, "refund failed");
        }

        emit BridgeInitiated(
            msg.sender,
            bridgeAmount,
            destinationDomain,
            recipient,
            nonce
        );
    }

    /// @notice Complete bridge on destination chain (anyone can call with valid attestation)
    /// @param message CCTP message from source chain MessageSent event
    /// @param attestation Circle attestation from https://iris-api.circle.com/v1/attestations/{messageHash}
    /// @dev This function can be called by anyone - it's permissionless
    function receiveUSDC(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool success) {
        // Circle MessageTransmitter will validate the attestation
        // and mint USDC to the recipient specified in the message
        success = messageTransmitter.receiveMessage(message, attestation);
        
        if (success) {
            // Extract recipient and amount from message for event
            // Message format: see Circle CCTP docs for parsing
            bytes32 messageHash = keccak256(message);
            emit BridgeCompleted(address(0), 0, messageHash);
        }
    }

    /// @notice Set bridge fee (only owner)
    /// @param newFee New fee in basis points (0-1000, i.e. 0-10%)
    function setFee(uint256 newFee) external onlyOwner {
        if (newFee > MAX_FEE_BPS) revert InvalidFee(newFee);
        uint256 oldFee = bridgeFee;
        bridgeFee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }

    /// @notice Set fee recipient (only owner)
    /// @param newRecipient New fee recipient address
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /// @notice Get estimated bridge fee for an amount
    /// @param amount Amount to bridge
    /// @return fee Fee amount that would be charged
    function quoteFee(uint256 amount) external view returns (uint256 fee) {
        fee = (amount * bridgeFee) / BPS_DENOMINATOR;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
