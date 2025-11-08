# Deployment Scripts Guide

## Overview

This guide covers the deployment scripts for the YieldDonating Strategy system, including both factory-based and direct deployment methods.

## 🏭 Factory-Based Deployment (Recommended)

The factory approach provides automated deployment, validation, and contract linking.

### Benefits of Factory Deployment
- ✅ **Automated validation** of all configurations
- ✅ **Automatic contract linking** between Strategy and SecurityRouter
- ✅ **Deployment tracking** and registry
- ✅ **Simplified process** with single transaction
- ✅ **Emergency recovery** functions
- ✅ **Configuration templates** for common setups

### Quick Start with Factory

**Easiest Method - Using Makefile**:
```bash
# 1. Setup environment
make setup-env
nano .env.deployment  # Edit with your addresses

# 2. Deploy everything
make deploy-factory

# 3. Done! Both contracts deployed and linked automatically
```

**Alternative - Manual Script**:
```bash
# 1. Configure Environment
cp deployment.env.example .env.deployment
# Edit .env.deployment with your addresses

# 2. Deploy Everything
source .env.deployment
forge script script/DeployWithFactory.s.sol --rpc-url $RPC_URL --broadcast --verify
```

**Note**: The factory automatically deploys the `TokenizedStrategy` implementation - no need to set `TOKENIZED_STRATEGY_IMPLEMENTATION`!

## 📋 Deployment Scripts

### 1. DeployWithFactory.s.sol (Recommended)

**Purpose**: Deploy complete system using the factory pattern

**Features**:
- Deploys or uses existing factory
- Validates all configurations
- Deploys Strategy + SecurityRouter in one transaction
- Automatically links contracts
- Provides comprehensive verification

**Usage**:
```bash
# With environment file
source .env.deployment
forge script script/DeployWithFactory.s.sol --rpc-url $RPC_URL --broadcast --verify

# With inline parameters
ADMIN_ADDRESS=0x... KEEPER_ADDRESS=0x... forge script script/DeployWithFactory.s.sol --rpc-url $RPC_URL --broadcast
```

### 2. DeployYieldDonatingStrategy.s.sol (Direct)

**Purpose**: Deploy contracts directly without factory

**Features**:
- Step-by-step deployment process
- Manual configuration validation
- Detailed verification steps
- Complete deployment summary

**Usage**:
```bash
# Configure addresses in script or use environment variables
forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## 🏗️ YieldDonatingStrategyFactory Contract

The factory contract automatically handles `TokenizedStrategy` implementation deployment and simplifies strategy creation.

### Factory Features

```solidity
contract YieldDonatingStrategyFactory {
    // Constructor - automatically deploys TokenizedStrategy implementation
    constructor(
        address _management,
        address _donationAddress,  // SecurityRouter address
        address _keeper,
        address _emergencyAdmin
    );
    
    // Deploy new strategy
    function newStrategy(
        address _compounderVault,  // Spark Vault address
        address _asset,            // USDC token address
        string calldata _name      // Strategy name
    ) external returns (address);
    
    // Configuration management
    function setAddresses(address _management, address _donationAddress, address _keeper) external;
    function setEnableBurning(bool _enableBurning) external;
    
    // Deployment tracking
    function isDeployedStrategy(address _strategy) external view returns (bool);
    function deployments(address _asset) external view returns (address);  // asset => strategy
    
    // Immutable properties
    address public immutable EMERGENCY_ADMIN;
    address public immutable TOKENIZED_STRATEGY_ADDRESS;  // Auto-deployed in constructor
}
```

### Key Benefits

- ✅ **Automatic Implementation**: `TokenizedStrategy` implementation is deployed automatically in constructor
- ✅ **No Manual Setup**: No need to manage implementation addresses
- ✅ **Simple Interface**: Just provide yield source, asset, and name
- ✅ **Deployment Tracking**: Tracks strategies by asset address
- ✅ **Configuration Management**: Update addresses and settings via management role

## ⚙️ Environment Configuration

### Required Environment Variables

```bash
# Network Configuration
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
PRIVATE_KEY=0x...

# Role Addresses (CRITICAL)
ADMIN_ADDRESS=0x...           # Admin role for SecurityRouter
KEEPER_ADDRESS=0x...          # Keeper for epoch management and reports
MANAGEMENT_ADDRESS=0x...      # Strategy management role
EMERGENCY_ADMIN_ADDRESS=0x... # Emergency shutdown authority
CANTINA_OPERATOR_ADDRESS=0x... # Cantina's operator for project approval

# Strategy Configuration
STRATEGY_NAME="USDC Spark YieldDonating Strategy"

# Optional: Use existing factory
FACTORY_ADDRESS=0x...  # Leave empty to deploy new factory

# Network-Specific Addresses (already set in scripts, but can override)
TEST_ASSET_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48  # USDC
TEST_YIELD_SOURCE=0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d   # Spark Vault
```

### Important Notes

- ✅ **No `TOKENIZED_STRATEGY_IMPLEMENTATION` needed**: Factory automatically deploys it
- ✅ **No `ENABLE_BURNING` needed**: Factory defaults to `true`, can be changed via `setEnableBurning()`
- ✅ **Minimal configuration**: Only roles, asset, and strategy name required

## 🚀 Step-by-Step Deployment

### Method 1: Factory Deployment with Makefile (Easiest - Recommended)

```bash
# 1. Setup environment file
make setup-env
nano .env.deployment  # Configure all addresses

# 2. Check environment configuration
make check-env

# 3. Deploy complete system
make deploy-factory

# 4. Test deployment
make test-deployment

# 5. Initialize first epoch
make init-epoch

# 6. Register and approve test project
make register-test-project
make approve-test-project
```

**That's it!** The Makefile handles everything automatically.

### Method 2: Factory Deployment (Manual Script)

```bash
# 1. Setup environment
cp deployment.env.example .env.deployment
nano .env.deployment  # Configure all addresses

# 2. Load environment
source .env.deployment

# 3. Deploy with factory
forge script script/DeployWithFactory.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --gas-limit 5000000

# 4. Save addresses from output
# FACTORY_ADDRESS=0x...
# STRATEGY_ADDRESS=0x...
# SECURITY_ROUTER_ADDRESS=0x...
```

### Method 3: Direct Deployment (Without Factory)

```bash
# 1. Configure addresses in script or environment
# Edit script/DeployYieldDonatingStrategy.s.sol

# 2. Deploy contracts
make deploy-direct
# OR manually:
forge script script/DeployYieldDonatingStrategy.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify

# 3. Verify deployment manually
make test-deployment
# OR manually:
cast call $STRATEGY_ADDRESS "dragonRouter()"
cast call $SECURITY_ROUTER_ADDRESS "YIELD_STRATEGY()"
```

### Quick Reference: Makefile Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make setup-env` | Create `.env.deployment` from template |
| `make check-env` | Verify environment configuration |
| `make deploy-factory` | Deploy with factory (recommended) |
| `make deploy-direct` | Deploy without factory |
| `make test-deployment` | Test deployed contracts |
| `make init-epoch` | Initialize first epoch |
| `make register-test-project` | Register a test project |
| `make approve-test-project` | Approve test project (Cantina) |
| `make check-status` | Check system status |
| `make advance-epoch` | Advance to next epoch |
| `make factory-info` | Get factory information |
| `make verify` | Verify contracts on Etherscan |

## 🔍 Post-Deployment Verification

### Automated Verification (Factory)

The factory deployment script includes comprehensive verification:

```bash
# Factory automatically verifies:
✅ Role assignments
✅ Contract configuration
✅ Asset compatibility
✅ Contract linking
✅ Deployment registry
```

### Manual Verification Commands

```bash
# Verify Strategy configuration
cast call $STRATEGY_ADDRESS "YIELD_SOURCE()"  # Should return Spark Vault
cast call $STRATEGY_ADDRESS "asset()"         # Should return USDC
cast call $STRATEGY_ADDRESS "dragonRouter()"  # Should return SecurityRouter

# Verify SecurityRouter configuration
cast call $SECURITY_ROUTER_ADDRESS "ASSET()"           # Should return USDC
cast call $SECURITY_ROUTER_ADDRESS "YIELD_STRATEGY()"  # Should return Strategy
cast call $SECURITY_ROUTER_ADDRESS "currentEpoch()"   # Should return 0

# Verify roles
cast call $SECURITY_ROUTER_ADDRESS "hasRole(bytes32,address)" \
    $(cast keccak "KEEPER_ROLE") $KEEPER_ADDRESS  # Should return true

# Test basic functionality
cast call $STRATEGY_ADDRESS "availableDepositLimit(address)" $USER_ADDRESS
cast call $STRATEGY_ADDRESS "availableWithdrawLimit(address)" $USER_ADDRESS
```

## 🧪 Testing Deployment

### Factory Testing

**Using Makefile**:
```bash
make factory-info  # Get factory information
make test-deployment  # Test all deployed contracts
```

**Manual Commands**:
```bash
# Check if strategy is tracked by factory
cast call $FACTORY_ADDRESS "isDeployedStrategy(address)" $STRATEGY_ADDRESS

# Get strategy address for an asset
cast call $FACTORY_ADDRESS "deployments(address)" $USDC_ADDRESS

# Get factory configuration
cast call $FACTORY_ADDRESS "management()"
cast call $FACTORY_ADDRESS "donationAddress()"
cast call $FACTORY_ADDRESS "keeper()"
cast call $FACTORY_ADDRESS "EMERGENCY_ADMIN()"
cast call $FACTORY_ADDRESS "TOKENIZED_STRATEGY_ADDRESS()"
cast call $FACTORY_ADDRESS "enableBurning()"
```

### Functional Testing

```bash
# 1. Initialize first epoch
cast send $SECURITY_ROUTER_ADDRESS "advanceEpoch()" --from $KEEPER_ADDRESS

# 2. Test small deposit (1 USDC)
cast send $USDC_ADDRESS "approve(address,uint256)" $STRATEGY_ADDRESS 1000000 --from $USER_ADDRESS
cast send $STRATEGY_ADDRESS "deposit(uint256,address)" 1000000 $USER_ADDRESS --from $USER_ADDRESS

# 3. Check strategy state
cast call $STRATEGY_ADDRESS "totalAssets()"
cast call $STRATEGY_ADDRESS "balanceOf(address)" $USER_ADDRESS

# 4. Register test project
cast send $SECURITY_ROUTER_ADDRESS "registerProject(string,string)" \
    "Test Project" "ipfs://test-metadata" --from $PROJECT_ADDRESS

# 5. Approve project (Cantina)
cast send $SECURITY_ROUTER_ADDRESS "approveProject(uint256)" 1 --from $CANTINA_OPERATOR_ADDRESS
```

## 🛠️ Advanced Usage

### Using Existing Factory

**With Makefile**:
```bash
# Set factory address in environment file
echo "FACTORY_ADDRESS=0x..." >> .env.deployment

# Deploy new strategy using existing factory
make deploy-factory
```

**Manual**:
```bash
# Set factory address in environment
export FACTORY_ADDRESS=0x...

# Deploy new strategy using existing factory
forge script script/DeployWithFactory.s.sol --rpc-url $RPC_URL --broadcast
```

### Updating Factory Configuration

```bash
# Update factory addresses (management role only)
cast send $FACTORY_ADDRESS "setAddresses(address,address,address)" \
    $NEW_MANAGEMENT $NEW_DONATION_ADDRESS $NEW_KEEPER \
    --from $MANAGEMENT_ADDRESS

# Update burning setting (management role only)
cast send $FACTORY_ADDRESS "setEnableBurning(bool)" false \
    --from $MANAGEMENT_ADDRESS
```

### Custom Configuration

Edit the deployment script to customize:
- Yield source (default: Spark Vault)
- Asset address (default: USDC)
- Strategy name
- Role addresses

### Multi-Network Deployment

```bash
# Deploy on different networks
forge script script/DeployWithFactory.s.sol --rpc-url $MAINNET_RPC --broadcast
forge script script/DeployWithFactory.s.sol --rpc-url $POLYGON_RPC --broadcast
forge script script/DeployWithFactory.s.sol --rpc-url $ARBITRUM_RPC --broadcast
```

## 🚨 Security Checklist

### Pre-Deployment
- [ ] All role addresses verified and controlled
- [ ] Private keys secured (hardware wallet recommended)
- [ ] Network and contract addresses double-checked
- [ ] Gas limits and prices configured appropriately
- [ ] Testnet deployment completed successfully

### Post-Deployment
- [ ] Contract verification on Etherscan completed
- [ ] All role assignments verified
- [ ] Contract linking confirmed
- [ ] Basic functionality tested
- [ ] Addresses saved securely
- [ ] Monitoring and alerting configured

### Production Checklist
- [ ] Multi-signature wallets for admin roles
- [ ] Keeper bot deployed and tested
- [ ] Emergency procedures documented
- [ ] Team access and permissions configured
- [ ] Insurance and risk management in place

## 🔧 Troubleshooting

### Common Issues

#### "Asset mismatch" Error
```bash
# Ensure Spark Vault asset matches USDC
cast call $SPARK_VAULT "asset()"  # Should return USDC address
```

#### "Not authorized" Error
```bash
# Check role assignments
cast call $SECURITY_ROUTER_ADDRESS "hasRole(bytes32,address)" \
    $(cast keccak "ADMIN_ROLE") $ADMIN_ADDRESS
```

#### Gas Estimation Failed
```bash
# Increase gas limit
forge script ... --gas-limit 8000000
```

### Recovery Procedures

#### Manual Linking (Direct)
```bash
cast send $SECURITY_ROUTER_ADDRESS "setStrategy(address)" \
    $STRATEGY_ADDRESS --from $ADMIN_ADDRESS
```

## 📊 Gas Costs

### Estimated Gas Usage

| Operation | Gas Cost | USD (20 gwei) |
|-----------|----------|---------------|
| Deploy Factory | ~2,500,000 | ~$100 |
| Deploy Complete System | ~4,000,000 | ~$160 |
| Deploy SecurityRouter | ~2,000,000 | ~$80 |
| Deploy Strategy | ~2,000,000 | ~$80 |
| Link Contracts | ~50,000 | ~$2 |

### Gas Optimization Tips

1. **Batch Operations**: Deploy multiple strategies in one transaction
2. **Factory Reuse**: Use existing factory for multiple deployments
3. **Optimal Gas Price**: Monitor network conditions
4. **Contract Size**: Minimize deployment bytecode size

## 📝 Summary

### Key Simplifications

1. **No Implementation Address Needed**: The factory automatically deploys `TokenizedStrategy` implementation
2. **Minimal Configuration**: Only role addresses and strategy name required
3. **Easy Makefile Commands**: Simple commands for all operations
4. **Automatic Linking**: Contracts are linked automatically during deployment

### Recommended Workflow

```bash
# 1. Quick setup
make setup-env && nano .env.deployment

# 2. Deploy everything
make deploy-factory

# 3. Verify and test
make test-deployment
make init-epoch

# 4. Monitor
make check-status
```

### What Changed from Previous Version

- ✅ **Removed**: `TOKENIZED_STRATEGY_IMPLEMENTATION` environment variable (auto-deployed)
- ✅ **Removed**: `ENABLE_BURNING` environment variable (defaults to true, can be changed)
- ✅ **Simplified**: Factory interface - just `newStrategy(yieldSource, asset, name)`
- ✅ **Added**: Comprehensive Makefile commands for easy deployment
- ✅ **Improved**: Better documentation with Makefile examples

---

This deployment system provides a robust, secure, and user-friendly way to deploy the YieldDonating Strategy with SecurityRouter system. The factory pattern ensures consistency and reduces deployment complexity while maintaining full configurability.

**For the easiest deployment experience, use the Makefile commands!** 🚀
