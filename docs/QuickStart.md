# Quick Start Guide

## 🚀 Get Started in 5 Minutes

### 1. Clone and Setup
```bash
git clone <repository-url>
cd octant-v2-strategy-foundry-mix
forge install && forge soldeer install
cp .env.example .env
```

### 2. Configure Environment
```bash
# Edit .env file
TEST_ASSET_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  # USDC
TEST_YIELD_SOURCE=0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d   # Spark Vault
ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
```

### 3. Run Tests
```bash
# Run all tests
make test

# Run specific test suite
forge test --match-contract YieldDonatingBugBountyFlow -vv --fork-url $ETH_RPC_URL
```

## 📋 Key Commands

### Testing
```bash
# All tests
make test

# With traces
make trace

# Specific contract
forge test --match-contract YieldDonatingOperation -vv --fork-url $ETH_RPC_URL

# Gas report
forge test --gas-report --fork-url $ETH_RPC_URL
```

### Deployment (Testnet)
```bash
# Deploy SecurityRouter
forge create SecurityRouter --constructor-args $USDC $ADMIN $KEEPER $CANTINA

# Deploy YieldDonatingStrategy  
forge create YieldDonatingStrategy --constructor-args $SPARK_VAULT $USDC "Strategy Name" $MANAGEMENT $KEEPER $EMERGENCY_ADMIN $SECURITY_ROUTER true $TOKENIZED_STRATEGY

# Link contracts
cast send $SECURITY_ROUTER "setStrategy(address)" $STRATEGY
```

## 🔧 Key Contracts

### YieldDonatingStrategy
- **Purpose**: Generate yield from USDC deposits in Spark Vault
- **Location**: `src/strategies/yieldDonating/YieldDonatingStrategy.sol`
- **Key Functions**: `_deployFunds()`, `_freeFunds()`, `_harvestAndReport()`

### SecurityRouter
- **Purpose**: Distribute yield as bug bounty rewards
- **Location**: `src/router/SecurityRouter.sol`  
- **Key Functions**: `registerProject()`, `approveProject()`, `submitBugReports()`

## 📊 Reward Formula

### Constants
- **Total Cap**: 25% of available funds per epoch
- **Per-Issue Cap**: 5% of total available funds per bug
- **Severity Weights**: Critical(5), High(3), Medium(2), Low(1), Info(1)

### Calculation
```solidity
finalPayout = min(
    severityBasedPayout,
    proportionalCap,
    maxPerIssue
);
```

## 🧪 Test Results

### Normal Fund Pool (362K USDC)
- Critical: 18,121 USDC (5% cap hit)
- Medium: 16,474 USDC each
- Low/Info: 8,237 USDC each
- Total: 67,543 USDC distributed

### Large Fund Pool (1.09M USDC)
- Critical: 54,497 USDC (5% cap hit)
- Medium: 54,497 USDC (5% cap hit)
- Low: 34,060 USDC (proportional)

## 📚 Documentation

- **[README.md](../README.md)**: Project overview and setup
- **[Architecture.md](Architecture.md)**: System design and components
- **[SecurityRouter.md](SecurityRouter.md)**: Detailed SecurityRouter guide
- **[Deployment.md](Deployment.md)**: Production deployment guide
- **[Testing.md](Testing.md)**: Comprehensive testing guide

## 🔗 Key Addresses (Mainnet)

```solidity
USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
SPARK_VAULT = 0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d
```

## ❓ Need Help?

1. **Check the logs**: Use `-vv` or `-vvv` for detailed output
2. **Verify environment**: Ensure `ETH_RPC_URL` is set correctly
3. **Check documentation**: Detailed guides in `/docs` folder
4. **Common issues**: See [Testing.md](Testing.md#debugging-common-issues)

---

**Ready to build the future of Web3 security! 🛡️**