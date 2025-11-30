# Chainlink Feed Mirror - Testing Guide

## Overview

Mirror Chainlink price feeds from an origin chain to destination chains using Reactive Network's CRON functionality. The system automatically reads all registered feeds and updates destination mirrors every ~20 minutes.

## Environment Variables

```bash
# Private Keys
export SEPOLIA_PRIVATE_KEY=your_SEPOLIA_PRIVATE_KEY_here

# RPC URLs
export SEPOLIA_RPC= "YOUR ORIGIN CHAIN RPC" [using sepolia rpc here]
export DEST_RPC="YOUR DESTINATION CHAIN RPC" [FOR testnet using sepolia as both origin and destination listing to sepolia chainlink price feed and passing the info to new contract deployed on sepolia if this works mainnet crosschains will work]
export REACTIVE_RPC=https://lasna-rpc.rnk.dev/

# System Contracts
export SYSTEM_CONTRACT=0x0000000000000000000000000000000000fffFfF
export CRON_TOPIC=0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687 # Get from Reactive Network docs

# Chainlink Feed (ETH/USD on SEPOLIA)
export CHAINLINK_ETH_USD=0x694AA1769357215DE4FAC081bf1f309aDC325306

# Deployer Address
export DEPLOYER_ADDR=$(cast wallet address $SEPOLIA_PRIVATE_KEY)
```

## Deployment Steps

### Step 1 — Deploy FeedReader (Origin Chain)

If not already deployed:

```bash
forge create --broadcast --rpc-url $SEPOLIA_RPC --private-key $SEPOLIA_PRIVATE_KEY \
  src/cross-chain-oracle/origin-chain-contracts/FeedReader.sol:FeedReader \
  --constructor-args $SEPOLIA_CALLBACK_PROXY_ADDR 3600 --value 0.001ether

export FEED_READER_ADDR=0x...
```

### Step 2 — Deploy FeedMirror (Destination Chain)

```bash
$ forge create --broadcast --rpc-url $DEST_RPC --private-key $SEPOLIA_PRIVATE_KEY \
  src/cross-chain-oracle/destination-chain-contracts/FeedMirror.sol:FeedMirror --constructor-args $SEPOLIA_CALLBACK_PROXY_ADDR

export FEED_MIRROR_ADDR=0x...
```

Initialize the FeedMirror:

```bash
cast send $FEED_MIRROR_ADDR "initialize(address,uint64,uint8,string)" \
  $CHAINLINK_ETH_USD 11155111 8 "ETH / USD" \
  --rpc-url $DEST_RPC --private-key $SEPOLIA_PRIVATE_KEY
```

### Step 3 — Register Feed in FeedReader

```bash
cast send $FEED_READER_ADDR "registerFeed(address,uint64,address,string)" \
  $CHAINLINK_ETH_USD 11155111 $FEED_MIRROR_ADDR "ETH/USD" \
  --rpc-url $SEPOLIA_RPC --private-key $SEPOLIA_PRIVATE_KEY
```

Verify registration:

```bash
cast call $FEED_READER_ADDR "getActiveFeeds()" --rpc-url $SEPOLIA_RPC
```

### Step 4 — Deploy Reactive Contract

```bash
forge create --broadcast --rpc-url $REACTIVE_RPC --private-key $SEPOLIA_PRIVATE_KEY \
  --value 1ether \
  src/cross-chain-oracle/reactive-smart-contracts/CrossChaiReactive.sol:ChainlinkFeedMirrorReactive \
  --constructor-args \
    $DEPLOYER_ADDR \
    $FEED_READER_ADDR \
    11155111 \
    $SYSTEM_CONTRACT \
    $CRON_TOPIC

export REACTIVE_ADDR=0x...
```

## Testing

### Manual Trigger (Don't wait for CRON)

```bash
cast send $REACTIVE_ADDR "manualTrigger()" \
  --rpc-url $REACTIVE_RPC --private-key $SEPOLIA_PRIVATE_KEY
```

Wait 2-3 minutes, then check destination:

```bash
cast call $FEED_MIRROR_ADDR "latestRoundData()" --rpc-url $DEST_RPC
```

### Verify Price Data

Compare origin vs destination:

```bash
# Origin (Chainlink)
echo "=== Origin Price ==="
cast call $CHAINLINK_ETH_USD "latestRoundData()" --rpc-url $SEPOLIA_RPC

# Destination (FeedMirror)
echo "=== Destination Price ==="
cast call $FEED_MIRROR_ADDR "latestRoundData()" --rpc-url $DEST_RPC
```

## Adding More Feeds

### Register Additional Feed

```bash
# Example: BTC/USD
export CHAINLINK_BTC_USD=0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c

# Deploy another FeedMirror
forge create --rpc-url $DEST_RPC --private-key $SEPOLIA_PRIVATE_KEY \
  src/FeedMirror.sol:FeedMirror

export FEED_MIRROR_BTC=0x...

# Initialize
cast send $FEED_MIRROR_BTC "initialize(address,uint64,uint8,string)" \
  $CHAINLINK_BTC_USD 1 8 "BTC / USD" \
  --rpc-url $DEST_RPC --private-key $SEPOLIA_PRIVATE_KEY

# Register in FeedReader
cast send $FEED_READER_ADDR "registerFeed(address,uint64,address,string)" \
  $CHAINLINK_BTC_USD 11155111 $FEED_MIRROR_BTC "BTC/USD" \
  --rpc-url $SEPOLIA_RPC --private-key $SEPOLIA_PRIVATE_KEY

# Set reactive as updater
cast send $FEED_MIRROR_BTC "setReactiveUpdater(address)" \
  $REACTIVE_ADDR \
  --rpc-url $DEST_RPC --private-key $SEPOLIA_PRIVATE_KEY
```

Next CRON will automatically pick up the new feed!

```

### Check Contract Balances

```bash
# Reactive contract balance
cast balance $REACTIVE_ADDR --rpc-url $REACTIVE_RPC

# Top up if needed
cast send $REACTIVE_ADDR --value 0.1ether \
  --rpc-url $REACTIVE_RPC --private-key $SEPOLIA_PRIVATE_KEY
```

## Troubleshooting

### CRON Not Executing

```bash
# Check balance
cast balance $REACTIVE_ADDR --rpc-url $REACTIVE_RPC

# Fund if low
cast send $REACTIVE_ADDR --value 0.1ether \
  --rpc-url $REACTIVE_RPC --private-key $SEPOLIA_PRIVATE_KEY
```

### Manual Recovery

```bash
# Force trigger
cast send $REACTIVE_ADDR "manualTrigger()" \
  --rpc-url $REACTIVE_RPC --private-key $SEPOLIA_PRIVATE_KEY

# Emergency update on destination
cast send $FEED_MIRROR_ADDR "emergencyUpdate(uint80,int256,uint256,uint256,uint80)" \
  [roundId] [answer] [startedAt] [updatedAt] [answeredInRound] \
  --rpc-url $DEST_RPC --private-key $SEPOLIA_PRIVATE_KEY
```

## Expected Behavior

1. **Deployment**: All contracts deployed, feeds registered
2. **Manual Trigger**: Prices appear on destination within 2-3 minutes
3. **CRON Cycle**: System updates automatically every ~20 minutes
4. **Multiple Feeds**: All registered feeds update in single CRON trigger


## Quick Commands

```bash
# Deploy reactive
forge create --rpc-url $REACTIVE_RPC --private-key $SEPOLIA_PRIVATE_KEY \
  --value 0.1ether --constructor-args $DEPLOYER_ADDR $FEED_READER_ADDR 1 $SYSTEM_CONTRACT $CRON_TOPIC \
  src/ChainlinkFeedMirrorReactive.sol:ChainlinkFeedMirrorReactive

# Test trigger
cast send $REACTIVE_ADDR "manualTrigger()" \
  --rpc-url $REACTIVE_RPC --private-key $SEPOLIA_PRIVATE_KEY

# Check result
cast call $FEED_MIRROR_ADDR "latestRoundData()" --rpc-url $DEST_RPC

# Monitor CRON
cast call $REACTIVE_ADDR "getLastCronInfo()" --rpc-url $REACTIVE_RPC
```



## TRANSACTIONS

The feed reader transaction can be found here https://sepolia.etherscan.io/address/0xfA564A493641F0A7eb62C390DD5FCBdD989A05C4#events

Link to feed mirror can be found here https://sepolia.etherscan.io/address/0x2B51D7a1a2D5c9Abc6b7E81f94a5a5d2088d1A0D#events

RVM transaction can be found here https://lasna.reactscan.net/address/0xd2aa84af3aba300908c6b1ae81df3b7db2edd06b/contract/0x362811d59f82f62903e2f0afc607e4d7d6b0449a?screen=transactions


Initilization transactions of reader can be found here https://sepolia.etherscan.io/address/0xfA564A493641F0A7eb62C390DD5FCBdD989A05C4

