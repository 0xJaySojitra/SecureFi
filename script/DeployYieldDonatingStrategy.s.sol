// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {YieldDonatingStrategy} from "../src/strategies/yieldDonating/YieldDonatingStrategy.sol";
import {SecurityRouter} from "../src/router/SecurityRouter.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

/**
 * @title Deploy YieldDonating Strategy with SecurityRouter
 * @notice Complete deployment script for the yield-funded bug bounty system
 * @dev Run with: forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployYieldDonatingStrategy is Script {
    
    // ============ CONFIGURATION ============
    
    // Mainnet addresses (update for other networks)
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SPARK_VAULT = 0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d;
    
    // Role addresses (configure these before deployment)
    struct DeploymentConfig {
        address admin;           // Admin role for both contracts
        address keeper;          // Keeper for epoch management and reports  
        address management;      // Strategy management
        address emergencyAdmin;  // Emergency shutdown authority
        address cantinaOperator; // Cantina's operator address
        string strategyName;     // Name for the strategy
        bool enableBurning;      // Whether to enable loss protection
    }
    
    // ============ DEPLOYED CONTRACTS ============
    
    SecurityRouter public securityRouter;
    YieldDonatingStrategy public strategy;
    
    // ============ DEPLOYMENT FUNCTIONS ============
    
    function run() external {
        // Get deployment configuration
        DeploymentConfig memory config = getDeploymentConfig();
        
        // Validate configuration
        validateConfig(config);
        
        console2.log("=== STARTING DEPLOYMENT ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", msg.sender);
        console2.log("USDC:", USDC);
        console2.log("Spark Vault:", SPARK_VAULT);
        
        vm.startBroadcast();
        
        // Step 1: Deploy SecurityRouter first (no dependencies)
        console2.log("\n=== STEP 1: DEPLOYING SECURITY ROUTER ===");
        securityRouter = deploySecurityRouter(config);
        
        // Step 2: Deploy YieldDonatingStrategy with SecurityRouter as dragonRouter
        console2.log("\n=== STEP 2: DEPLOYING YIELD DONATING STRATEGY ===");
        strategy = deployYieldDonatingStrategy(config, address(securityRouter));
        
        // Step 3: Link contracts (set strategy address in SecurityRouter)
        console2.log("\n=== STEP 3: LINKING CONTRACTS ===");
        linkContracts();
        
        vm.stopBroadcast();
        
        // Step 4: Verify deployment
        console2.log("\n=== STEP 4: VERIFYING DEPLOYMENT ===");
        verifyDeployment(config);
        
        // Step 5: Print deployment summary
        console2.log("\n=== DEPLOYMENT COMPLETED SUCCESSFULLY ===");
        printDeploymentSummary(config);
    }
    
    /**
     * @notice Deploy SecurityRouter contract
     */
    function deploySecurityRouter(DeploymentConfig memory config) internal returns (SecurityRouter) {
        SecurityRouter router = new SecurityRouter(
            USDC,                    // asset - USDC token
            config.admin,            // admin role
            config.keeper,           // keeper role
            config.cantinaOperator   // cantina role
        );
        
        console2.log("SecurityRouter deployed at:", address(router));
        console2.log("- Asset (USDC):", router.ASSET());
        console2.log("- Admin role granted to:", config.admin);
        console2.log("- Keeper role granted to:", config.keeper);
        console2.log("- Cantina role granted to:", config.cantinaOperator);
        
        return router;
    }
    
    /**
     * @notice Deploy YieldDonatingStrategy contract
     */
    function deployYieldDonatingStrategy(
        DeploymentConfig memory config,
        address dragonRouter
    ) internal returns (YieldDonatingStrategy) {
        // Deploy TokenizedStrategy implementation (same as factory does)
        address tokenizedStrategyAddress = address(new YieldDonatingTokenizedStrategy());
        console2.log("TokenizedStrategy implementation deployed at:", tokenizedStrategyAddress);
        
        YieldDonatingStrategy yieldStrategy = new YieldDonatingStrategy(
            SPARK_VAULT,                        // yieldSource - Spark Vault
            USDC,                              // asset - USDC token
            config.strategyName,               // name
            config.management,                 // management role
            config.keeper,                     // keeper role
            config.emergencyAdmin,             // emergencyAdmin role
            dragonRouter,                      // dragonRouter - SecurityRouter
            config.enableBurning,              // enableBurning - loss protection
            tokenizedStrategyAddress            // tokenizedStrategy implementation
        );
        
        console2.log("YieldDonatingStrategy deployed at:", address(yieldStrategy));
        console2.log("- Yield Source (Spark Vault):", yieldStrategy.YIELD_SOURCE());
        console2.log("- Asset (USDC):", yieldStrategy.asset());
        console2.log("- Dragon Router:", yieldStrategy.dragonRouter());
        console2.log("- Management:", yieldStrategy.management());
        console2.log("- Keeper:", yieldStrategy.keeper());
        console2.log("- Emergency Admin:", yieldStrategy.emergencyAdmin());
        console2.log("- Burning Enabled:", yieldStrategy.enableBurning());
        
        return yieldStrategy;
    }
    
    /**
     * @notice Link contracts by setting strategy address in SecurityRouter
     */
    function linkContracts() internal {
        securityRouter.setStrategy(address(strategy));
        
        console2.log("Contracts linked successfully");
        console2.log("- SecurityRouter.YIELD_STRATEGY:", address(securityRouter.YIELD_STRATEGY()));
        
        // Verify the link
        require(
            address(securityRouter.YIELD_STRATEGY()) == address(strategy),
            "Contract linking failed"
        );
    }
    
    /**
     * @notice Verify deployment was successful
     */
    function verifyDeployment(DeploymentConfig memory config) internal view {
        console2.log("Verifying SecurityRouter...");
        
        // Verify SecurityRouter roles
        require(securityRouter.hasRole(securityRouter.DEFAULT_ADMIN_ROLE(), config.admin), "Admin role not set");
        require(securityRouter.hasRole(securityRouter.KEEPER_ROLE(), config.keeper), "Keeper role not set");
        require(securityRouter.hasRole(securityRouter.CANTINA_ROLE(), config.cantinaOperator), "Cantina role not set");
        
        // Verify SecurityRouter asset
        require(address(securityRouter.ASSET()) == USDC, "Wrong asset in SecurityRouter");
        
        console2.log("Verifying YieldDonatingStrategy...");
        
        // Verify YieldDonatingStrategy configuration
        require(address(strategy.YIELD_SOURCE()) == SPARK_VAULT, "Wrong yield source");
        require(strategy.asset() == USDC, "Wrong asset in strategy");
        require(strategy.dragonRouter() == address(securityRouter), "Wrong dragon router");
        require(strategy.management() == config.management, "Wrong management");
        require(strategy.keeper() == config.keeper, "Wrong keeper");
        require(strategy.emergencyAdmin() == config.emergencyAdmin, "Wrong emergency admin");
        require(strategy.enableBurning() == config.enableBurning, "Wrong burning setting");
        
        console2.log("Verifying contract linking...");
        
        // Verify contracts are linked
        require(address(securityRouter.YIELD_STRATEGY()) == address(strategy), "Contracts not linked");
        
        console2.log("✅ All verifications passed!");
    }
    
    /**
     * @notice Print deployment summary with all important information
     */
    function printDeploymentSummary(DeploymentConfig memory config) internal view {
        console2.log("\n📋 DEPLOYMENT SUMMARY");
        console2.log("=====================");
        
        console2.log("\n🏗️ DEPLOYED CONTRACTS:");
        console2.log("SecurityRouter:        ", address(securityRouter));
        console2.log("YieldDonatingStrategy: ", address(strategy));
        
        console2.log("\n🔑 ROLE ASSIGNMENTS:");
        console2.log("Admin:           ", config.admin);
        console2.log("Keeper:          ", config.keeper);
        console2.log("Management:      ", config.management);
        console2.log("Emergency Admin: ", config.emergencyAdmin);
        console2.log("Cantina Operator:", config.cantinaOperator);
        
        console2.log("\n⚙️ CONFIGURATION:");
        console2.log("Strategy Name:   ", config.strategyName);
        console2.log("Burning Enabled: ", config.enableBurning ? "Yes" : "No");
        console2.log("USDC Asset:     ", USDC);
        console2.log("Spark Vault:    ", SPARK_VAULT);
        
        console2.log("\n📊 LIMITS & STATUS:");
        console2.log("Deposit Limit:   ", strategy.availableDepositLimit(address(0)));
        console2.log("Withdraw Limit:  ", strategy.availableWithdrawLimit(address(0)));
        console2.log("Current Epoch:   ", securityRouter.currentEpoch());
        console2.log("Available Funds: ", securityRouter.getAvailableFunds());
        
        console2.log("\n🚀 NEXT STEPS:");
        console2.log("1. Initialize first epoch: securityRouter.advanceEpoch()");
        console2.log("2. Test small deposit: strategy.deposit(1000000, user) // 1 USDC");
        console2.log("3. Register test project: securityRouter.registerProject()");
        console2.log("4. Set up keeper bot for automated epoch management");
        console2.log("5. Configure monitoring and alerting");
        
        console2.log("\n⚠️  IMPORTANT NOTES:");
        console2.log("- Save all contract addresses for future reference");
        console2.log("- Test with small amounts before full deployment");
        console2.log("- Set up proper monitoring for keeper operations");
        console2.log("- Ensure Cantina has the correct operator address");
    }
    
    /**
     * @notice Get deployment configuration
     * @dev Override this function or set environment variables
     */
    function getDeploymentConfig() internal view returns (DeploymentConfig memory) {
        // Try to get from environment variables first
        address admin = vm.envOr("ADMIN_ADDRESS", address(0));
        address keeper = vm.envOr("KEEPER_ADDRESS", address(0));
        address management = vm.envOr("MANAGEMENT_ADDRESS", address(0));
        address emergencyAdmin = vm.envOr("EMERGENCY_ADMIN_ADDRESS", address(0));
        address cantinaOperator = vm.envOr("CANTINA_OPERATOR_ADDRESS", address(0));
        
        // If not set in env, use default test addresses (WARNING: NOT FOR PRODUCTION)
        if (admin == address(0)) {
            console2.log("⚠️  WARNING: Using default test addresses. Set environment variables for production!");
            
            return DeploymentConfig({
                admin: 0x1234567890123456789012345678901234567890,           // TODO: Replace
                keeper: 0x2345678901234567890123456789012345678901,          // TODO: Replace
                management: 0x3456789012345678901234567890123456789012,      // TODO: Replace
                emergencyAdmin: 0x4567890123456789012345678901234567890,    // TODO: Replace
                cantinaOperator: 0x5678901234567890123456789012345678901,   // TODO: Replace
                strategyName: "USDC Spark YieldDonating Strategy",
                enableBurning: true
            });
        }
        
        return DeploymentConfig({
            admin: admin,
            keeper: keeper,
            management: management,
            emergencyAdmin: emergencyAdmin,
            cantinaOperator: cantinaOperator,
            strategyName: vm.envOr("STRATEGY_NAME", "USDC Spark YieldDonating Strategy"),
            enableBurning: vm.envOr("ENABLE_BURNING", true)
        });
    }
    
    /**
     * @notice Validate deployment configuration
     */
    function validateConfig(DeploymentConfig memory config) internal pure {
        require(config.admin != address(0), "Admin address cannot be zero");
        require(config.keeper != address(0), "Keeper address cannot be zero");
        require(config.management != address(0), "Management address cannot be zero");
        require(config.emergencyAdmin != address(0), "Emergency admin address cannot be zero");
        require(config.cantinaOperator != address(0), "Cantina operator address cannot be zero");
        require(bytes(config.strategyName).length > 0, "Strategy name cannot be empty");
        
        // Ensure no role conflicts (same address shouldn't have multiple critical roles)
        require(config.admin != config.keeper, "Admin and keeper should be different");
        require(config.admin != config.emergencyAdmin, "Admin and emergency admin should be different");
    }
}
