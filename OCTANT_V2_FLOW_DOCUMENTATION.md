# Octant V2 - Complete System Flow Documentation

## Overview

This document explains the complete end-to-end flow of the Octant V2 yield donation system integrated with the SecurityRouter for bug bounty rewards distribution via Cantina.

## System Architecture

```
┌─────────────┐
│   Users     │ ← Deposit USDC
└──────┬──────┘
       │
       ▼
┌──────────────────────────────┐
│ YieldDonatingStrategy        │ ← ERC4626 Vault (Strategy Token)
│  (Tokenized Strategy)        │
└──────┬───────────────────────┘
       │
       ├─→ Deploys USDC to
       │
       ▼
┌──────────────────────────────┐
│   Aave USDC Vault           │ ← ERC4626 Vault (Aave aToken wrapper)
│   (ERC4626)                 │
└──────┬───────────────────────┘
       │
       └─→ Earns yield from Aave lending
       
When Profit Detected:
       
       ┌──────────────────────────────┐
       │ YieldDonatingStrategy        │
       │  .report() called            │
       └──────┬───────────────────────┘
              │
              ├─→ Mints profit shares to:
              │
              ▼
       ┌──────────────────────────────┐
       │   SecurityRouter             │ ← Dragon Router
       │   (Donation Receiver)        │
       └──────┬───────────────────────┘
              │
              ├─→ Redeems shares for USDC
              │
              ▼
       ┌──────────────────────────────┐
       │  Bug Bounty Rewards          │
       │  (Distributed via Cantina)   │
       └──────────────────────────────┘
```

## Key Contracts and Their Roles

### 1. YieldDonatingStrategy (Your Strategy Contract)
- **Type**: ERC4626 Vault + ERC20 (shares)
- **Purpose**: Manages user deposits and deploys funds to Aave vault
- **Key Functions**:
  - `deposit(uint256 assets, address receiver)` - Users deposit USDC, receive strategy shares
  - `_deployFunds(uint256 amount)` - Deploys USDC to Aave vault
  - `_harvestAndReport()` - Calculates total assets (deployed + idle)
  - `report()` - Inherited from YieldDonatingTokenizedStrategy, mints profit shares to dragon router
  - `redeem(uint256 shares, address receiver, address owner)` - Redeems shares for underlying USDC
  - `_freeFunds(uint256 amount)` - Withdraws USDC from Aave vault

### 2. YieldDonatingTokenizedStrategy (Core Logic)
- **Type**: TokenizedStrategy implementation
- **Purpose**: Handles profit/loss reporting and donation share minting
- **Key Function**:
  - `report()` - Called by keeper, triggers:
    1. Calls `_harvestAndReport()` to get current total assets
    2. Compares with previous total assets
    3. If profit: Mints shares equal to profit to `dragonRouter` address
    4. If loss and burning enabled: Burns dragon router shares

### 3. SecurityRouter (Dragon Router Contract)
- **Type**: Access-controlled reward distribution contract
- **Purpose**: Receives donated yield shares and distributes as bug bounty rewards
- **Key Functions**:
  - `triggerStrategyReport()` - Keeper calls to trigger profit reporting and share minting
  - `advanceEpoch()` - Keeper calls to redeem shares for USDC at epoch end
  - `submitBugReports()` - Cantina submits bug reports and triggers reward distribution

### 4. Aave USDC Vault (External)
- **Type**: ERC4626 wrapper around Aave aUSDC
- **Purpose**: Provides yield through Aave lending protocol
- **Reference**: https://github.com/aave/Aave-Vault

## Complete Flow: From Deposit to Reward Distribution

### Phase 1: Initial Setup and Deposit

```solidity
// 1. Deploy YieldDonatingStrategy with SecurityRouter as dragonRouter
YieldDonatingStrategy strategy = new YieldDonatingStrategy(
    aaveVaultAddress,        // _yieldSource (Aave ERC4626 vault)
    usdcAddress,             // _asset
    "Aave USDC Strategy",    // _name
    managementAddress,       // _management
    keeperAddress,           // _keeper
    emergencyAdminAddress,   // _emergencyAdmin
    securityRouterAddress,   // _donationAddress (dragon router)
    true,                    // _enableBurning
    tokenizedStrategyAddress // _tokenizedStrategyAddress
);

// 2. User deposits USDC
strategy.deposit(1000e6, userAddress);
// → User receives strategy shares (1:1 initially)
// → Calls _deployFunds() internally
// → Strategy deposits USDC into Aave vault
// → Strategy receives Aave vault shares
```

### Phase 2: Yield Accrual

```solidity
// Time passes... Aave vault earns yield from lending
// - Users deposit and borrow from Aave
// - Interest accrues on supplied USDC
// - Aave vault share value increases
// - Strategy's position grows in value
```

### Phase 3: Harvest and Profit Reporting (Every Epoch)

```solidity
// Keeper triggers report at end of epoch (e.g., every 30 days)

// Step 1: Trigger strategy report
securityRouter.triggerStrategyReport(); // Called by keeper
// ↓
strategy.report(); // Inherited from YieldDonatingTokenizedStrategy
// ↓ Internally:
// 1. Calls _harvestAndReport()
uint256 idleAssets = IERC20(asset).balanceOf(address(strategy));
uint256 sharesBalance = YIELD_SOURCE.balanceOf(address(strategy)); // Aave vault shares
uint256 deployedAssets = YIELD_SOURCE.convertToAssets(sharesBalance); // Convert to USDC value
uint256 newTotalAssets = idleAssets + deployedAssets;

// 2. Compare with oldTotalAssets
uint256 profit = newTotalAssets - oldTotalAssets; // e.g., 100 USDC profit

// 3. Mint shares to dragonRouter (SecurityRouter)
uint256 sharesToMint = convertToShares(profit); // e.g., 100 shares
_mint(securityRouter, sharesToMint);
emit DonationMinted(securityRouter, sharesToMint);

// Result: SecurityRouter now has 100 strategy shares representing the yield
```

### Phase 4: Epoch Advancement and Reward Preparation

```solidity
// Keeper advances epoch after report
securityRouter.advanceEpoch(); // Called by keeper after 30 days
// ↓ Internally:

// Step 1: Get accumulated shares
uint256 shares = yieldStrategy.balanceOf(address(this)); // 100 shares

// Step 2: Redeem shares for USDC
uint256 usdcAmount = yieldStrategy.redeem(
    shares,              // 100 shares
    address(this),       // receiver (SecurityRouter)
    address(this)        // owner (SecurityRouter)
);
// ↓ This triggers in YieldDonatingStrategy:
// - _freeFunds(100 USDC) is called
// - Strategy withdraws 100 USDC from Aave vault
// - Aave vault burns its shares
// - 100 USDC transferred to SecurityRouter

// Step 3: Record epoch data
epochs[currentEpoch] = EpochData({
    totalYield: 100e6,          // 100 USDC available
    totalProjects: 5,            // 5 approved projects
    distributedAmount: 0,
    finalized: false
});

// Result: SecurityRouter now has 100 USDC ready for distribution
```

### Phase 5: Bug Bounty Distribution

```solidity
// Cantina submits bug reports for a project
securityRouter.submitBugReports(
    epoch,                    // e.g., epoch 1
    projectId,               // e.g., project #3
    bugReports,              // Array of {reportId, reporter, severity}
    cantinaSignature         // Cantina's verification signature
);
// ↓ Internally:

// Step 1: Calculate project allocation
uint256 projectYield = 100e6 / 5; // 20 USDC per project

// Step 2: Calculate weighted distribution
// Critical bug: 5 points, High: 3 points, Medium: 2 points, Low: 1 point
// Example: 1 Critical (5pts) + 2 High (6pts) = 11 total points

// Step 3: Distribute to reporters
for (each bug report) {
    uint256 weight = getSeverityWeight(severity);
    uint256 payout = (20e6 * weight) / 11; // Proportional share
    
    // Transfer USDC to security researcher
    asset.safeTransfer(reporter, payout);
    
    emit BugPayoutExecuted(epoch, projectId, reporter, payout, severity);
}

// Result: Security researchers receive USDC rewards funded by yield
```

## Function Call Sequence Diagram

```
┌─────────┐     ┌──────────────┐     ┌────────────────────┐     ┌─────────────┐
│  User   │     │    Keeper    │     │ SecurityRouter     │     │  Strategy   │
└────┬────┘     └──────┬───────┘     └─────────┬──────────┘     └──────┬──────┘
     │                 │                       │                        │
     │  deposit(1000)  │                       │                        │
     ├─────────────────┼───────────────────────┼───────────────────────>│
     │                 │                       │   _deployFunds(1000)   │
     │                 │                       │   ↓ deposits to Aave   │
     │<────────────────┼───────────────────────┼────────────────────────┤
     │  shares received│                       │                        │
     │                 │                       │                        │
     │                 │   [Time passes... yield accrues in Aave]       │
     │                 │                       │                        │
     │                 │ triggerStrategyReport()│                       │
     │                 ├───────────────────────>│                        │
     │                 │                       │   report()             │
     │                 │                       ├───────────────────────>│
     │                 │                       │   _harvestAndReport()  │
     │                 │                       │   ↓ calculates profit  │
     │                 │                       │<───┐ mint shares to    │
     │                 │                       │    │ SecurityRouter    │
     │                 │  shares minted ✓      │<───┘                   │
     │                 │<──────────────────────┤                        │
     │                 │                       │                        │
     │                 │  advanceEpoch()       │                        │
     │                 ├───────────────────────>│                        │
     │                 │                       │  redeem(shares)        │
     │                 │                       ├───────────────────────>│
     │                 │                       │   _freeFunds()         │
     │                 │                       │   ↓ withdraw from Aave │
     │                 │  USDC received ✓      │<───────────────────────┤
     │                 │<──────────────────────┤                        │
     │                 │                       │                        │
┌────┴────┐            │                       │                        │
│ Cantina │            │                       │                        │
└────┬────┘            │                       │                        │
     │  submitBugReports(epoch, project, bugs) │                        │
     ├─────────────────┼───────────────────────>│                        │
     │                 │                       │  ↓ distribute USDC     │
     │                 │                       │    to researchers      │
     │                 │  rewards distributed ✓│                        │
     │<────────────────┼───────────────────────┤                        │
```

## Key Concepts

### 1. Dragon Router
- The "dragonRouter" is the address that receives minted profit shares
- In our system, `SecurityRouter` is the dragon router
- When strategy reports profit, shares are automatically minted to this address

### 2. Share Minting vs Asset Transfer
- **Profit is donated as SHARES, not assets**
- Shares represent a claim on underlying assets
- SecurityRouter holds shares until ready to distribute rewards
- Shares are redeemed for actual USDC when needed

### 3. _freeFunds() Trigger
- Called automatically during `redeem()` or `withdraw()`
- When SecurityRouter redeems shares → Strategy calls `_freeFunds()`
- `_freeFunds()` withdraws USDC from Aave vault to strategy
- Strategy then transfers USDC to SecurityRouter

### 4. Two-Vault System
- **YieldDonatingStrategy**: User-facing vault, manages deposits/withdrawals
- **Aave Vault**: Underlying yield source, holds the actual USDC

## Deployment Checklist

### 1. Deploy Contracts
```solidity
// 1. Deploy SecurityRouter first (or use existing)
SecurityRouter router = new SecurityRouter(
    address(0), // Will set strategy after deployment
    cantinaAddress,
    adminAddress,
    keeperAddress
);

// 2. Deploy YieldDonatingStrategy
YieldDonatingStrategy strategy = new YieldDonatingStrategy(
    aaveUsdcVaultAddress,  // External Aave vault
    usdcAddress,
    "Octant Aave USDC",
    managementAddress,
    keeperAddress,
    emergencyAdminAddress,
    address(router),       // Dragon router
    true,                  // Enable burning
    tokenizedStrategyAddress
);

// 3. Update SecurityRouter with strategy address (if needed)
// This depends on your constructor design
```

### 2. Grant Roles
```solidity
// SecurityRouter roles
router.grantRole(KEEPER_ROLE, keeperAddress);
router.grantRole(CANTINA_ROLE, cantinaAddress);
router.grantRole(ADMIN_ROLE, adminAddress);
```

### 3. Verify Integration
```solidity
// Check that router is set as dragon router
address dragonRouter = strategy.dragonRouter();
require(dragonRouter == address(router), "Router not set correctly");
```

## Keeper Bot Operations

### Daily/Regular Operations
```javascript
// Keeper bot should monitor:

// 1. Check if epoch should advance (every 30 days)
const timeRemaining = await router.getCurrentEpochTimeRemaining();
if (timeRemaining == 0) {
    // Trigger report first
    await router.triggerStrategyReport();
    
    // Then advance epoch
    await router.advanceEpoch();
}

// 2. Monitor strategy health
const totalAssets = await strategy.totalAssets();
const idleAssets = await usdc.balanceOf(strategy.address);
const deployedAssets = totalAssets - idleAssets;

// 3. Check accumulated donations
const pendingShares = await router.getAccumulatedShares();
const pendingValue = await router.getAccumulatedAssetValue();
```

## Security Considerations

### 1. Access Control
- `KEEPER_ROLE`: Can trigger reports and advance epochs
- `CANTINA_ROLE`: Can approve projects and submit bug reports
- `ADMIN_ROLE`: Can manage roles and emergency functions

### 2. Epoch Finalization
- Epochs must be finalized before rewards can be distributed
- Prevents double-spending of yield
- Cantina signature required for bug report submissions

### 3. Asset Safety
- Strategy uses `SafeERC20` for all transfers
- Aave vault limits are checked before deposits
- Emergency withdrawal functions available

## Common Issues and Solutions

### Issue 1: No yield being donated
**Cause**: Keeper not calling `report()` regularly
**Solution**: Set up keeper bot to call `triggerStrategyReport()` before epoch advance

### Issue 2: Cannot redeem shares
**Cause**: Insufficient liquidity in Aave vault
**Solution**: `_freeFunds()` handles partial withdrawals gracefully

### Issue 3: Incorrect reward calculations
**Cause**: Epoch not advanced after report
**Solution**: Always call `triggerStrategyReport()` then `advanceEpoch()` in sequence

## Testing Scenarios

### Test 1: Full Cycle
```solidity
// 1. User deposits 1000 USDC
// 2. Time passes, yield accrues (simulate by donating to Aave)
// 3. Keeper calls triggerStrategyReport() → shares minted to router
// 4. Keeper calls advanceEpoch() → USDC transferred to router
// 5. Cantina submits bug reports → rewards distributed
```

### Test 2: Multiple Epochs
```solidity
// Test that yield accumulates across epochs
// Test that old epochs can still distribute after new epoch starts
```

### Test 3: No Yield Scenario
```solidity
// Test that system works correctly when no profit is generated
// Should not mint any shares to router
```

## Summary

The Octant V2 system creates a virtuous cycle:
1. **Users** deposit USDC to earn strategy shares
2. **Strategy** deploys USDC to Aave for yield
3. **Yield** is converted to strategy shares and minted to SecurityRouter
4. **SecurityRouter** redeems shares for USDC
5. **USDC** is distributed as bug bounty rewards to security researchers
6. **Security researchers** help protect projects that couldn't afford audits
7. **Users** get principal back anytime, yield goes to public good

This creates **sustainable funding for web3 security** through **DeFi yield generation**! 🚀

