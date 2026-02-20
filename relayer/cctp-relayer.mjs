#!/usr/bin/env node
/**
 * CCTP Relayer - Auto-mint USDC on destination chain
 * 
 * How it works:
 * 1. Monitor MessageSent events on source chain
 * 2. Get attestation from Circle API
 * 3. Call receiveMessage on destination chain
 * 
 * Usage:
 *   node cctp-relayer.mjs --watch
 */

import { ethers } from 'ethers';
import fs from 'fs';

// Config
const CONFIG = {
  // Source chain (Polygon)
  source: {
    rpc: 'https://polygon-bor-rpc.publicnode.com',
    tokenMessenger: '0x9daF8c91AEFAE50b9c0E69629D3F6Ca40cA3B3FE',
    chainName: 'Polygon'
  },
  
  // Destination chain (Arbitrum)
  destination: {
    rpc: 'https://arb1.arbitrum.io/rpc',
    messageTransmitter: '0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca',
    chainName: 'Arbitrum'
  },
  
  // Circle API
  circleAPI: 'https://iris-api.circle.com/v1/attestations',
  
  // Polling interval (seconds)
  pollInterval: 60,
  
  // Attestation retry config
  attestationRetries: 20,
  attestationRetryInterval: 30000 // 30 seconds
};

const TOKEN_MESSENGER_ABI = [
  'event MessageSent(bytes message)'
];

const MESSAGE_TRANSMITTER_ABI = [
  'function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success)',
  'event MessageReceived(address indexed caller, uint32 sourceDomain, uint64 indexed nonce, bytes32 sender, bytes messageBody)'
];

class CCTPRelayer {
  constructor(privateKey) {
    // Source chain
    this.sourceProvider = new ethers.JsonRpcProvider(CONFIG.source.rpc);
    this.sourceContract = new ethers.Contract(
      CONFIG.source.tokenMessenger,
      TOKEN_MESSENGER_ABI,
      this.sourceProvider
    );
    
    // Destination chain
    this.destProvider = new ethers.JsonRpcProvider(CONFIG.destination.rpc);
    this.destWallet = new ethers.Wallet(privateKey, this.destProvider);
    this.destContract = new ethers.Contract(
      CONFIG.destination.messageTransmitter,
      MESSAGE_TRANSMITTER_ABI,
      this.destWallet
    );
    
    this.processedMessages = new Set();
  }

  async getAttestation(messageHash, retries = CONFIG.attestationRetries) {
    for (let i = 0; i < retries; i++) {
      try {
        const url = `${CONFIG.circleAPI}/${messageHash}`;
        const response = await fetch(url);
        const data = await response.json();
        
        if (data.status === 'complete' && data.attestation) {
          return data.attestation;
        }
        
        if (i < retries - 1) {
          console.log(`   ⏳ Attestation pending... retry ${i + 1}/${retries}`);
          await new Promise(r => setTimeout(r, CONFIG.attestationRetryInterval));
        }
      } catch (error) {
        console.error(`   ❌ Attestation API error: ${error.message}`);
      }
    }
    
    return null;
  }

  async processMessage(message, messageHash, txHash) {
    console.log(`\n📨 Processing message: ${messageHash}`);
    console.log(`   Source TX: https://polygonscan.com/tx/${txHash}`);
    
    // Check if already processed
    if (this.processedMessages.has(messageHash)) {
      console.log('   ⏭️  Already processed, skipping');
      return;
    }
    
    try {
      // Get attestation
      console.log('   🔄 Fetching attestation from Circle...');
      const attestation = await this.getAttestation(messageHash);
      
      if (!attestation) {
        console.log('   ❌ Failed to get attestation after retries');
        return;
      }
      
      console.log('   ✅ Attestation received');
      
      // Call receiveMessage on destination chain
      console.log(`   🎁 Calling receiveMessage on ${CONFIG.destination.chainName}...`);
      
      const tx = await this.destContract.receiveMessage(message, attestation);
      console.log(`   TX submitted: ${tx.hash}`);
      console.log(`   Waiting for confirmation...`);
      
      const receipt = await tx.wait();
      console.log(`   ✅ Mint completed! Block: ${receipt.blockNumber}`);
      console.log(`   Arbitrum TX: https://arbiscan.io/tx/${tx.hash}`);
      
      // Mark as processed
      this.processedMessages.add(messageHash);
      
      return {
        messageHash,
        sourceTx: txHash,
        destTx: tx.hash,
        blockNumber: receipt.blockNumber
      };
      
    } catch (error) {
      console.error(`   ❌ Processing failed: ${error.message}`);
      return null;
    }
  }

  async watchNewMessages() {
    console.log('\n🚀 CCTP Relayer Started');
    console.log('=====================================');
    console.log(`Source: ${CONFIG.source.chainName}`);
    console.log(`Destination: ${CONFIG.destination.chainName}`);
    console.log(`Relayer: ${this.destWallet.address}`);
    console.log('=====================================\n');
    
    let lastBlock = await this.sourceProvider.getBlockNumber();
    console.log(`📍 Starting from block: ${lastBlock}\n`);
    
    while (true) {
      try {
        const currentBlock = await this.sourceProvider.getBlockNumber();
        
        if (currentBlock > lastBlock) {
          console.log(`🔍 Scanning blocks ${lastBlock + 1} to ${currentBlock}...`);
          
          // Query MessageSent events
          const events = await this.sourceContract.queryFilter(
            this.sourceContract.filters.MessageSent(),
            lastBlock + 1,
            currentBlock
          );
          
          if (events.length > 0) {
            console.log(`   Found ${events.length} message(s)\n`);
            
            for (const event of events) {
              const message = event.args.message;
              const messageHash = ethers.keccak256(message);
              const txHash = event.transactionHash;
              
              await this.processMessage(message, messageHash, txHash);
            }
          } else {
            console.log(`   No new messages`);
          }
          
          lastBlock = currentBlock;
        }
        
      } catch (error) {
        console.error(`❌ Watch error: ${error.message}`);
      }
      
      // Wait before next poll
      await new Promise(r => setTimeout(r, CONFIG.pollInterval * 1000));
    }
  }

  async processExisting(txHash) {
    console.log(`\n🔍 Processing existing transaction: ${txHash}`);
    
    const tx = await this.sourceProvider.getTransaction(txHash);
    if (!tx) {
      console.error('❌ Transaction not found');
      return;
    }
    
    const receipt = await this.sourceProvider.getTransactionReceipt(txHash);
    
    // Find MessageSent event
    const event = receipt.logs.find(log => {
      try {
        const parsed = this.sourceContract.interface.parseLog(log);
        return parsed && parsed.name === 'MessageSent';
      } catch {
        return false;
      }
    });
    
    if (!event) {
      console.error('❌ No MessageSent event found');
      return;
    }
    
    const parsed = this.sourceContract.interface.parseLog(event);
    const message = parsed.args.message;
    const messageHash = ethers.keccak256(message);
    
    await this.processMessage(message, messageHash, txHash);
  }
}

// CLI
async function main() {
  const args = process.argv.slice(2);
  
  // Load wallet
  const walletConfig = JSON.parse(
    fs.readFileSync('/root/.openclaw/workspace/.secrets/tangyuan-wallet.json', 'utf8')
  );
  
  const relayer = new CCTPRelayer(walletConfig.privateKey);
  
  if (args.includes('--watch')) {
    // Watch mode
    await relayer.watchNewMessages();
  } else if (args.includes('--tx')) {
    // Process specific transaction
    const txIndex = args.indexOf('--tx') + 1;
    const txHash = args[txIndex];
    if (!txHash) {
      console.error('❌ Usage: --tx <transaction_hash>');
      process.exit(1);
    }
    await relayer.processExisting(txHash);
  } else {
    console.log('CCTP Relayer - Auto-mint USDC on destination chain');
    console.log('\nUsage:');
    console.log('  node cctp-relayer.mjs --watch              # Watch for new messages');
    console.log('  node cctp-relayer.mjs --tx <hash>          # Process specific transaction');
    console.log('\nExamples:');
    console.log('  node cctp-relayer.mjs --watch');
    console.log('  node cctp-relayer.mjs --tx 0xabc...');
  }
}

main().catch(console.error);
