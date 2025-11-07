# YieldDonating Strategy with SecurityRouter - Bug Bounty Rewards System

This project implements a **YieldDonating Strategy** that integrates with a **SecurityRouter** to create an innovative bug bounty rewards system. The strategy generates yield from ERC4626 vaults (Spark Vault) and donates 100% of profits to fund security bug bounties through Cantina integration.

## 🎯 Project Overview

### What This System Does:
- **YieldDonating Strategy**: Deploys USDC into Spark Vault to generate yield
- **SecurityRouter**: Acts as the "dragonRouter" to receive donated yield and distribute bug bounty rewards
- **Cantina Integration**: Connects with Cantina for project approval and bug report verification
- **Automated Rewards**: Distributes rewards to security researchers based on bug severity
- **Rollover Mechanism**: Unused funds carry over to the next epoch for larger reward pools

### Key Features:
- **25% Total Cap**: Uses 25% of available funds for monthly distribution
- **5% Per-Issue Cap**: No single bug can receive more than 5% of total available funds
- **Severity-Based Rewards**: Critical > High > Medium > Low > Informational
- **Cross-Epoch Support**: Projects can receive reports regardless of registration epoch
- **Loss Protection**: Optional burning of dragonRouter shares to protect users

## Getting Started

### Prerequisites

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation) (WSL recommended for Windows)
2. Install [Node.js](https://nodejs.org/en/download/package-manager/)
3. Clone this repository:
```sh
git clone git@github.com:golemfoundation/octant-v2-strategy-foundry-mix.git
```

4. Install dependencies:
```sh
forge install
forge soldeer install
```

### Environment Setup

1. Copy `.env.example` to `.env`
2. Set the required environment variables:
```env
# Required for testing - Spark Vault Integration
TEST_ASSET_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  # USDC on mainnet
TEST_YIELD_SOURCE=0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d   # Spark Vault address

# RPC URLs (Required for fork testing)
ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_API_KEY
```

3. Get your Alchemy API key from [alchemy.com](https://alchemy.com) for mainnet forking

## 🏗️ System Architecture

### Core Components

#### 1. YieldDonatingStrategy (`src/strategies/yieldDonating/YieldDonatingStrategy.sol`)
- **Purpose**: Generates yield by depositing USDC into Spark Vault (ERC4626)
- **Key Functions**:
  - `_deployFunds()`: Deposits USDC into Spark Vault
  - `_freeFunds()`: Withdraws USDC from Spark Vault
  - `_harvestAndReport()`: Reports total assets and triggers profit minting
  - `availableDepositLimit()` & `availableWithdrawLimit()`: Manages deposit/withdrawal limits

#### 2. SecurityRouter (`src/router/SecurityRouter.sol`)
- **Purpose**: Acts as "dragonRouter" to receive donated yield and distribute bug bounty rewards
- **Key Features**:
  - **Project Management**: Registration and approval by Cantina
  - **Epoch System**: Monthly cycles for yield collection and distribution
  - **Reward Distribution**: 25% total cap with 5% per-issue limit
  - **Cantina Integration**: Signature verification for bug reports
  - **Rollover Mechanism**: Unused funds carry over to next epoch

#### 3. Reward Distribution Formula
```solidity
// Constants
TOTAL_CAP_PERCENTAGE = 2500;  // 25% of available funds
MAX_ISSUE_PERCENTAGE = 500;   // 5% per individual issue

// For each bug report
severityBasedPayout = (projectYield * severityWeight) / projectTotalWeight;
proportionalCap = (totalCapPool * severityWeight) / globalTotalWeight;
maxPerIssue = (totalAvailableFunds * 500) / 10000;
finalPayout = min(severityBasedPayout, proportionalCap, maxPerIssue);
```

### Severity Weights
- **Critical**: 5 points
- **High**: 3 points  
- **Medium**: 2 points
- **Low**: 1 point
- **Informational**: 1 point

## 🧪 Testing the System

### Quick Start Testing

```sh
# Run all tests (requires mainnet fork)
make test

# Run specific test suites
forge test --match-contract YieldDonatingOperation -vv --fork-url $ETH_RPC_URL
forge test --match-contract YieldDonatingBugBountyFlow -vv --fork-url $ETH_RPC_URL
forge test --match-contract YieldDonatingShutdown -vv --fork-url $ETH_RPC_URL
```

### Test Suites Overview

#### 1. **YieldDonatingOperation.t.sol**
Tests basic strategy functionality:
- ✅ USDC deposit/withdrawal from Spark Vault
- ✅ Yield generation and profit minting to SecurityRouter
- ✅ Deposit/withdrawal limits enforcement

#### 2. **YieldDonatingBugBountyFlow.t.sol** 
Tests complete bug bounty flow:
- ✅ Project registration and Cantina approval
- ✅ Yield generation and epoch advancement
- ✅ Bug report submission with different severities
- ✅ Reward distribution with 25% total cap + 5% per-issue limit
- ✅ Cross-epoch reporting and rollover mechanism

#### 3. **YieldDonatingShutdown.t.sol**
Tests emergency scenarios:
- ✅ Emergency withdrawal functionality
- ✅ Strategy shutdown procedures
- ✅ Asset recovery mechanisms

### Key Test Results

**Normal Fund Pool (362K USDC)**:
- Critical bug: 18,121 USDC (hits 5% cap)
- Medium bugs: 16,474 USDC each
- Low/Info bugs: 8,237 USDC each
- Total distributed: 67,543 USDC (18.6%)
- Remaining for rollover: 294,894 USDC

**Large Fund Pool (1.09M USDC with rollover)**:
- Critical bug: 54,497 USDC (hits 5% cap)
- Medium bug: 54,497 USDC (hits 5% cap)
- Low bug: 34,060 USDC (proportional)
- Demonstrates cap protection and hierarchy maintenance

## 🚀 End-to-End Flow

### 1. **User Deposits USDC**
```
User → YieldDonatingStrategy → Spark Vault
```
- Users deposit USDC into the YieldDonatingStrategy
- Strategy automatically deploys funds to Spark Vault for yield generation

### 2. **Yield Generation & Collection**
```
Spark Vault → YieldDonatingStrategy → SecurityRouter (as shares)
```
- Keeper calls `report()` monthly to harvest yield
- Profits are minted as strategy shares to SecurityRouter
- SecurityRouter redeems shares for underlying USDC

### 3. **Project Registration & Approval**
```
Project → SecurityRouter → Cantina (approval) → SecurityRouter
```
- Projects register with metadata and funding goals
- Cantina reviews and approves worthy projects
- Only approved projects are eligible for bug bounty funding

### 4. **Bug Discovery & Reporting**
```
Security Researcher → Cantina → SecurityRouter (with signature)
```
- Researchers find bugs and report to Cantina
- Cantina verifies reports and submits to SecurityRouter with cryptographic signature
- Reports can be submitted for any approved project regardless of epoch

### 5. **Reward Distribution**
```
SecurityRouter → Security Researchers (USDC rewards)
```
- At epoch end, SecurityRouter distributes rewards based on:
  - **25% total cap** of available funds
  - **5% per-issue cap** to prevent single bug from draining funds
  - **Severity-based hierarchy** (Critical > Medium > Low > Info)
- Unused funds rollover to next epoch for larger reward pools

## 🔧 Deployment Guide

### Prerequisites
- Deployed Octant V2 core contracts
- Spark Vault integration
- Cantina partnership for project approval

### Deployment Steps

1. **Deploy SecurityRouter**
```solidity
SecurityRouter securityRouter = new SecurityRouter(
    USDC_ADDRESS,           // asset
    admin,                  // admin role
    keeper,                 // keeper role  
    cantinaOperator        // cantina role
);
```

2. **Deploy YieldDonatingStrategy**
```solidity
YieldDonatingStrategy strategy = new YieldDonatingStrategy(
    SPARK_VAULT_ADDRESS,                    // yieldSource
    USDC_ADDRESS,                          // asset
    "USDC Spark YieldDonating Strategy",   // name
    management,                            // management
    keeper,                               // keeper
    emergencyAdmin,                       // emergencyAdmin
    address(securityRouter),              // dragonRouter
    true,                                 // enableBurning
    TOKENIZED_STRATEGY_ADDRESS            // tokenizedStrategy
);
```

3. **Link Contracts**
```solidity
securityRouter.setStrategy(address(strategy));
```

### Configuration
- Set appropriate roles for each contract
- Configure epoch duration (default: 30 days)
- Set up Cantina operator permissions
- Test with small amounts before full deployment

## 🔒 Security Considerations

- **Access Control**: Role-based permissions for critical functions
- **Signature Verification**: Cantina reports verified cryptographically  
- **Cap Protection**: 5% per-issue limit prevents fund drainage
- **Emergency Shutdown**: Strategy can be paused and funds recovered
- **Loss Protection**: Optional burning of dragon shares protects users
- **Rollover Safety**: Unused funds safely carried to next epoch

## 🤝 Integration with Cantina

The SecurityRouter expects Cantina to:
1. **Review and approve** project applications
2. **Verify bug reports** from security researchers
3. **Submit signed reports** using the `submitBugReports()` function
4. **Maintain signature keys** for cryptographic verification

## 📊 Economics & Incentives

- **For Users**: Earn yield while supporting security research
- **For Projects**: Get security auditing without upfront costs
- **For Researchers**: Earn substantial rewards for finding bugs
- **For Ecosystem**: Improved overall security through continuous auditing

---

**Built with ❤️ for Web3 Security**


