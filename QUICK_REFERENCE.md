# Octant V2 - Quick Reference Guide

## Critical Contract Addresses & Roles

### YieldDonatingStrategy
- **What**: User-facing ERC4626 vault (strategy shares)
- **Holds**: Strategy shares for users + Aave vault shares
- **Dragon Router**: `SecurityRouter` contract address

### SecurityRouter  
- **What**: Dragon Router that receives donated yield
- **Holds**: Strategy shares (donated profits) + USDC (after redemption)
- **Role**: Distributes bug bounty rewards

### Aave USDC Vault
- **What**: External ERC4626 vault wrapping Aave aUSDC
- **Holds**: Actual USDC earning yield from Aave lending

## Key Functions & When to Call Them

### For Keeper Bot

```solidity
// STEP 1: Trigger report (at epoch end, e.g., every 30 days)
SecurityRouter.triggerStrategyReport()
// → Calls YieldDonatingStrategy.report()
// → Mints profit shares to SecurityRouter

// STEP 2: Advance epoch (right after report)
SecurityRouter.advanceEpoch()  
// → Redeems shares for USDC
// → Makes USDC available for rewards

// Check if epoch should advance
SecurityRouter.getCurrentEpochTimeRemaining() == 0
```

### For Cantina

```solidity
// Approve projects
SecurityRouter.approveProject(projectId)

// Submit bug reports and distribute rewards
SecurityRouter.submitBugReports(epoch, projectId, reports, signature)

// Finalize epoch (after all projects processed)
SecurityRouter.finalizeEpoch(epoch)
```

### For Users

```solidity
// Deposit USDC
YieldDonatingStrategy.deposit(amount, receiver)

// Withdraw USDC
YieldDonatingStrategy.redeem(shares, receiver, owner)

// Check balance
YieldDonatingStrategy.balanceOf(user)
YieldDonatingStrategy.convertToAssets(shares)
```

## Function Call Chain

### Deposit Flow
```
User.deposit(1000 USDC)
  → YieldDonatingStrategy.deposit()
    → YieldDonatingStrategy._deployFunds()
      → AaveVault.deposit(1000 USDC)
        → Strategy receives Aave shares
  → User receives Strategy shares
```

### Report & Donate Flow
```
Keeper.triggerStrategyReport()
  → SecurityRouter.triggerStrategyReport()
    → YieldDonatingStrategy.report()
      → YieldDonatingStrategy._harvestAndReport()
        → Calculate: idle USDC + Aave vault value
        → Detect profit
      → _mint(SecurityRouter, profitShares)
  → SecurityRouter now has strategy shares
```

### Redeem & Distribute Flow
```
Keeper.advanceEpoch()
  → SecurityRouter.advanceEpoch()
    → YieldDonatingStrategy.redeem(shares)
      → YieldDonatingStrategy._freeFunds()
        → AaveVault.withdraw(USDC)
          → USDC sent to Strategy
      → Strategy transfers USDC to SecurityRouter
  → SecurityRouter now has USDC

Cantina.submitBugReports()
  → SecurityRouter.submitBugReports()
    → asset.safeTransfer(reporter, payout)
  → Researchers receive USDC rewards
```

## Critical State Variables

### YieldDonatingStrategy
```solidity
address public immutable YIELD_SOURCE;  // Aave USDC vault
address public immutable asset;          // USDC token
address public dragonRouter;             // SecurityRouter address
uint256 public totalAssets;              // Tracked by TokenizedStrategy
```

### SecurityRouter
```solidity
IERC4626Strategy public immutable yieldStrategy;  // YieldDonatingStrategy
IERC20Metadata public immutable asset;            // USDC
uint256 public currentEpoch;
uint256 public epochStartTime;
uint256 public constant EPOCH_DURATION = 30 days;
```

## Important Checks

### Before Deposit
```solidity
// Check deposit limits
uint256 limit = strategy.availableDepositLimit(user);
require(amount <= limit, "Exceeds limit");
```

### Before Report
```solidity
// Ensure time has passed for yield to accrue
require(block.timestamp > lastReport + MIN_REPORT_DELAY);
```

### Before Epoch Advance
```solidity
// Must wait full epoch duration
require(block.timestamp >= epochStartTime + EPOCH_DURATION);

// Should call report first
// keeper.triggerStrategyReport();
// THEN
// keeper.advanceEpoch();
```

### Before Reward Distribution
```solidity
// Epoch must be completed
require(epoch < currentEpoch, "Epoch not finished");

// Epoch must have yield
require(epochs[epoch].totalYield > 0, "No yield");

// Epoch not already distributed
require(!epochs[epoch].finalized, "Already finalized");
```

## View Functions for Monitoring

### Strategy Status
```solidity
strategy.totalAssets()                          // Total USDC value
strategy.balanceOf(address)                     // Strategy shares held
strategy.convertToAssets(shares)                // Convert shares to USDC value
strategy.convertToShares(assets)                // Convert USDC to shares
```

### Router Status
```solidity
router.getAccumulatedShares()                   // Strategy shares held
router.getAccumulatedAssetValue()               // USDC value of shares
router.getCurrentEpochTimeRemaining()           // Seconds until epoch ends
router.getProjectReports(epoch, projectId)      // Bug reports for project
```

### Aave Vault Status
```solidity
aaveVault.balanceOf(address(strategy))          // Aave shares held by strategy
aaveVault.convertToAssets(shares)               // USDC value in Aave
aaveVault.totalAssets()                         // Total USDC in Aave vault
```

## Expected Values After Operations

### After User Deposit (1000 USDC)
```
User balance: 1000 strategy shares
Strategy idle USDC: 0 (deployed to Aave)
Strategy Aave shares: ~1000 (1:1 initially)
Strategy totalAssets: 1000 USDC
```

### After 30 Days (with 10 USDC yield)
```
Strategy Aave shares: ~1000 (same)
Aave vault value: 1010 USDC (increased)
Strategy totalAssets: 1010 USDC (via _harvestAndReport)
```

### After Report (with 10 USDC yield)
```
SecurityRouter shares: 10 strategy shares
SecurityRouter asset value: 10 USDC worth
Strategy totalAssets: 1010 USDC (unchanged)
User shares: 1000 (unchanged)
```

### After Epoch Advance
```
SecurityRouter shares: 0 (redeemed)
SecurityRouter USDC balance: 10 USDC
Strategy totalAssets: 1000 USDC (yield withdrawn)
Available for rewards: 10 USDC
```

### After Reward Distribution
```
SecurityRouter USDC balance: 0 (distributed)
Researchers USDC balance: 10 USDC total (split by severity)
Epoch finalized: true
```

## Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| "Epoch not finished" | Called advanceEpoch too early | Wait for full EPOCH_DURATION |
| "No yield for epoch" | No profit was generated | Normal - skip reward distribution |
| "DepositExceedsVaultLimit" | Aave vault is full | Wait or reduce deposit amount |
| "Not authorized" | Wrong role calling function | Use correct address with proper role |
| "Epoch already distributed" | Trying to submit reports twice | Check if epoch is finalized |

## Keeper Bot Pseudocode

```javascript
async function main() {
    while (true) {
        // Check if epoch should end
        const timeRemaining = await router.getCurrentEpochTimeRemaining();
        
        if (timeRemaining === 0) {
            console.log("Epoch ended, processing...");
            
            // Step 1: Trigger report to mint donation shares
            const tx1 = await router.triggerStrategyReport();
            await tx1.wait();
            console.log("Report triggered, shares minted to router");
            
            // Step 2: Advance epoch to redeem shares for USDC
            const tx2 = await router.advanceEpoch();
            await tx2.wait();
            console.log("Epoch advanced, USDC ready for distribution");
            
            // Log results
            const yieldAmount = await getEpochYield(currentEpoch - 1);
            console.log(`Yield available for rewards: ${yieldAmount} USDC`);
        }
        
        // Check again in 1 hour
        await sleep(3600 * 1000);
    }
}
```

## Emergency Procedures

### If Strategy Needs Emergency Shutdown
```solidity
// 1. Shutdown strategy (management only)
strategy.shutdownStrategy();

// 2. Emergency withdraw from Aave
strategy.emergencyWithdraw(amount);

// 3. Users can still withdraw their principal
user.redeem(shares, receiver, owner);
```

### If Router Needs to Return Funds
```solidity
// Admin can recover stuck tokens (if implemented)
router.recoverToken(tokenAddress, amount);
```

## Gas Optimization Tips

1. **Batch Operations**: Cantina should batch multiple bug reports in one `submitBugReports()` call
2. **Report Timing**: Call `report()` only when significant yield has accrued
3. **Approval**: Pre-approve Aave vault to avoid approval gas on each deposit

## Integration Testing Checklist

- [ ] Deploy all contracts with correct addresses
- [ ] Grant all roles correctly
- [ ] Test deposit → deploys to Aave
- [ ] Simulate yield accrual (time travel)
- [ ] Test report → mints shares to router
- [ ] Test advanceEpoch → redeems shares for USDC
- [ ] Test submitBugReports → distributes USDC
- [ ] Test user withdrawal → gets principal back
- [ ] Test emergency procedures
- [ ] Monitor gas costs for all operations

## Contract Deployment Order

1. Deploy or use existing **Aave USDC Vault** (external)
2. Deploy **SecurityRouter** (set strategy to address(0) initially)
3. Deploy **YieldDonatingStrategy** (with SecurityRouter as dragon router)
4. Update SecurityRouter with strategy address (if needed)
5. Grant roles on SecurityRouter
6. Test full flow with small amounts

## Recommended Configuration

```solidity
EPOCH_DURATION = 30 days          // Monthly reward cycles
MIN_REPORT_DELAY = 1 days         // Prevent spam reports
AAVE_VAULT = 0x...                // Aave's official ERC4626 vault
USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  // Mainnet USDC
```

---

**Remember**: The system is trustless and automated. Once set up correctly, it creates a sustainable cycle of yield generation → security funding → safer web3 ecosystem! 🛡️

