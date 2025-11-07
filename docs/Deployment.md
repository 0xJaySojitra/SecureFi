# Deployment Guide - YieldDonating Strategy with SecurityRouter

## Prerequisites

### Required Contracts
- **Octant V2 Core**: TokenizedStrategy implementation
- **Spark Vault**: ERC4626 vault for USDC yield generation
- **USDC Token**: ERC20 token contract on target network

### Required Addresses
```solidity
// Mainnet addresses
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant SPARK_VAULT = 0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d;
address constant TOKENIZED_STRATEGY = 0x...; // Octant V2 implementation

// Role addresses (to be configured)
address admin = 0x...;           // Admin role for both contracts
address keeper = 0x...;          // Keeper for epoch management and reports
address management = 0x...;      // Strategy management
address emergencyAdmin = 0x...;  // Emergency shutdown authority
address cantinaOperator = 0x...; // Cantina's operator address
```

## Step-by-Step Deployment

### 1. Deploy SecurityRouter

```solidity
// Deploy SecurityRouter first (no dependencies)
SecurityRouter securityRouter = new SecurityRouter(
    USDC,           // asset - USDC token
    admin,          // admin role
    keeper,         // keeper role
    cantinaOperator // cantina role
);

console.log("SecurityRouter deployed at:", address(securityRouter));
```

**Verification Steps:**
```solidity
// Verify roles are set correctly
assert(securityRouter.hasRole(securityRouter.DEFAULT_ADMIN_ROLE(), admin));
assert(securityRouter.hasRole(securityRouter.KEEPER_ROLE(), keeper));
assert(securityRouter.hasRole(securityRouter.CANTINA_ROLE(), cantinaOperator));

// Verify asset is correct
assert(securityRouter.ASSET() == IERC20Metadata(USDC));
```

### 2. Deploy YieldDonatingStrategy

```solidity
// Deploy strategy with SecurityRouter as dragonRouter
YieldDonatingStrategy strategy = new YieldDonatingStrategy(
    SPARK_VAULT,                           // yieldSource - Spark Vault
    USDC,                                  // asset - USDC token
    "USDC Spark YieldDonating Strategy",   // name
    management,                            // management role
    keeper,                               // keeper role
    emergencyAdmin,                       // emergencyAdmin role
    address(securityRouter),              // dragonRouter - SecurityRouter
    true,                                 // enableBurning - loss protection
    TOKENIZED_STRATEGY                    // tokenizedStrategy implementation
);

console.log("YieldDonatingStrategy deployed at:", address(strategy));
```

**Verification Steps:**
```solidity
// Verify configuration
assert(strategy.YIELD_SOURCE() == IERC4626(SPARK_VAULT));
assert(strategy.asset() == USDC);
assert(strategy.dragonRouter() == address(securityRouter));
assert(strategy.enableBurning() == true);

// Verify roles
assert(strategy.management() == management);
assert(strategy.keeper() == keeper);
assert(strategy.emergencyAdmin() == emergencyAdmin);
```

### 3. Link Contracts

```solidity
// Set strategy address in SecurityRouter to complete the link
securityRouter.setStrategy(address(strategy));

console.log("Contracts linked successfully");
```

**Verification Steps:**
```solidity
// Verify link is established
assert(securityRouter.YIELD_STRATEGY() == strategy);

// Test basic functionality
uint256 depositLimit = strategy.availableDepositLimit(address(0));
uint256 withdrawLimit = strategy.availableWithdrawLimit(address(0));
console.log("Deposit limit:", depositLimit);
console.log("Withdraw limit:", withdrawLimit);
```

## Post-Deployment Configuration

### 1. Initialize First Epoch

```solidity
// Keeper advances to epoch 1 to start the system
vm.prank(keeper);
securityRouter.advanceEpoch();

console.log("Current epoch:", securityRouter.currentEpoch());
console.log("Epoch start time:", securityRouter.epochStartTime());
```

### 2. Test Project Registration

```solidity
// Test project registration flow
address testProject = 0x123...;

vm.prank(testProject);
uint256 projectId = securityRouter.registerProject(
    "Test Project",
    "ipfs://test-metadata-hash"
);

// Cantina approves the project
vm.prank(cantinaOperator);
securityRouter.approveProject(projectId);

console.log("Test project registered and approved:", projectId);
```

### 3. Verify Token Approvals

```solidity
// Check that strategy can interact with Spark Vault
uint256 allowance = IERC20(USDC).allowance(address(strategy), SPARK_VAULT);
console.log("Strategy -> Spark Vault allowance:", allowance);

// Should be max uint256 for unlimited approval
assert(allowance == type(uint256).max);
```

## Testing Deployment

### 1. Small Deposit Test

```solidity
// Test with small amount first
uint256 testAmount = 1000 * 1e6; // 1000 USDC

// Mint USDC to test user
address testUser = 0x456...;
deal(USDC, testUser, testAmount);

// User deposits into strategy
vm.startPrank(testUser);
IERC20(USDC).approve(address(strategy), testAmount);
uint256 shares = ITokenizedStrategy(address(strategy)).deposit(testAmount, testUser);
vm.stopPrank();

console.log("Test deposit successful:");
console.log("- Amount:", testAmount);
console.log("- Shares received:", shares);
console.log("- Strategy total assets:", strategy.totalAssets());
```

### 2. Yield Generation Test

```solidity
// Simulate time passage and yield generation
skip(7 days);

// Keeper triggers report to harvest yield
vm.prank(keeper);
(uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();

console.log("First report results:");
console.log("- Profit:", profit);
console.log("- Loss:", loss);
console.log("- SecurityRouter shares:", ITokenizedStrategy(address(strategy)).balanceOf(address(securityRouter)));
```

### 3. Epoch Advancement Test

```solidity
// Advance epoch to collect yield
skip(30 days);

uint256 routerSharesBefore = ITokenizedStrategy(address(strategy)).balanceOf(address(securityRouter));

vm.prank(keeper);
securityRouter.advanceEpoch();

uint256 routerUSDCAfter = IERC20(USDC).balanceOf(address(securityRouter));

console.log("Epoch advancement results:");
console.log("- Router shares before:", routerSharesBefore);
console.log("- Router USDC after:", routerUSDCAfter);
console.log("- Available funds:", securityRouter.getAvailableFunds());
```

## Production Deployment Checklist

### Pre-Deployment
- [ ] Verify all contract addresses on target network
- [ ] Confirm role addresses and permissions
- [ ] Test deployment on testnet first
- [ ] Prepare deployment scripts with proper error handling
- [ ] Set up monitoring and alerting

### Deployment
- [ ] Deploy SecurityRouter with correct parameters
- [ ] Deploy YieldDonatingStrategy with correct parameters
- [ ] Link contracts via `setStrategy()`
- [ ] Verify all contract state is correct
- [ ] Initialize first epoch

### Post-Deployment
- [ ] Test small deposit/withdrawal
- [ ] Verify yield generation works
- [ ] Test epoch advancement
- [ ] Set up keeper automation
- [ ] Configure monitoring dashboards
- [ ] Document all deployed addresses

### Security
- [ ] Verify all role assignments
- [ ] Test emergency shutdown procedures
- [ ] Confirm signature verification works
- [ ] Set up multi-sig for admin functions
- [ ] Audit all contract interactions

## Monitoring & Maintenance

### Key Metrics to Monitor
- **Strategy Performance**: Total assets, yield generation rate
- **SecurityRouter Funds**: Available funds, distribution amounts
- **Epoch Health**: Regular advancement, rollover amounts
- **Project Activity**: Registration rate, approval rate
- **Bug Report Activity**: Submission frequency, reward distribution

### Automated Tasks
- **Epoch Advancement**: Keeper should advance epochs monthly
- **Strategy Reports**: Regular yield harvesting and reporting
- **Health Checks**: Monitor contract state and balances

### Emergency Procedures
- **Strategy Shutdown**: Emergency admin can pause strategy
- **Fund Recovery**: Admin can recover funds in emergency
- **Role Rotation**: Update keeper/cantina operators as needed

## Gas Optimization Tips

### Deployment
- Use CREATE2 for deterministic addresses
- Deploy with optimal compiler settings
- Consider proxy patterns for upgradeability

### Operations
- Batch multiple operations when possible
- Use efficient data structures
- Optimize for common use cases

## Troubleshooting

### Common Issues
1. **"call to non-contract address"**: Verify addresses on correct network
2. **"!keeper"**: Check role assignments and caller permissions
3. **"ERC4626: redeem more than max"**: Check vault liquidity and limits
4. **"Invalid signature"**: Verify Cantina signature generation

### Debug Tools
- Use Foundry's `forge verify-contract` for verification
- Enable detailed logging during deployment
- Use `cast` commands to query contract state
- Set up proper error handling and revert messages

---

This deployment guide ensures a smooth and secure deployment of the YieldDonating Strategy with SecurityRouter system.
