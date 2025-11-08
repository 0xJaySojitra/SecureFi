// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {YieldDonatingStrategyFactory} from "../src/strategies/yieldDonating/YieldDonatingStrategyFactory.sol";
import {SecurityRouter} from "../src/router/SecurityRouter.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title Deploy YieldDonating Strategy using Factory
 * @notice Simplified deployment script using the strategy factory
 * @dev Run with: forge script script/DeployWithFactory.s.sol --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployWithFactory is Script {
    
    // ============ CONFIGURATION ============
    
    // Mainnet addresses (update for other networks)
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SPARK_VAULT = 0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d;
    
    // ============ DEPLOYED CONTRACTS ============
    
    SecurityRouter public securityRouter;
    YieldDonatingStrategyFactory public factory;
    address public strategy;
    
    // ============ CONFIGURATION STRUCT ============
    
    struct DeploymentConfig {
        address admin;           // Admin role for SecurityRouter
        address keeper;          // Keeper role
        address management;      // Strategy management
        address emergencyAdmin;  // Emergency shutdown authority
        address cantinaOperator; // Cantina's operator address
        string strategyName;     // Name for the strategy
    }
    
    // ============ MAIN DEPLOYMENT FUNCTION ============
    
    function run() external {
        console2.log("=== DEPLOYING WITH FACTORY ===");
        console2.log("Network:", block.chainid);
        
        // Get configuration from environment
        DeploymentConfig memory config = getDeploymentConfig();
        validateConfig(config);
        
        // Start broadcast with private key from environment
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        // Step 1: Deploy SecurityRouter first
        console2.log("\n=== STEP 1: DEPLOYING SECURITY ROUTER ===");
        securityRouter = deploySecurityRouter(config);
        
        // Step 2: Deploy or use existing factory
        console2.log("\n=== STEP 2: FACTORY DEPLOYMENT ===");
        factory = deployOrGetFactory(config, address(securityRouter));
        
        // Step 3: Deploy strategy using factory
        console2.log("\n=== STEP 3: DEPLOYING STRATEGY WITH FACTORY ===");
        strategy = deployStrategyWithFactory(config);
        
        // Step 4: Link contracts
        console2.log("\n=== STEP 4: LINKING CONTRACTS ===");
        linkContracts(config);
        
        vm.stopBroadcast();
        
        // Step 5: Verify deployment
        console2.log("\n=== STEP 5: VERIFICATION ===");
        verifyDeployment(config);
        
        // Step 6: Print summary
        console2.log("\n=== DEPLOYMENT COMPLETED ===");
        printDeploymentSummary(config);
    }
    
    /**
     * @notice Deploy SecurityRouter contract
     */
    function deploySecurityRouter(DeploymentConfig memory config) internal returns (SecurityRouter) {
        SecurityRouter router = new SecurityRouter(
            config.cantinaOperator,  // cantina role
            config.admin,            // admin role
            config.keeper            // keeper role
        );
        
        console2.log("SecurityRouter deployed at:", address(router));
        console2.log("- Admin role granted to:", config.admin);
        console2.log("- Keeper role granted to:", config.keeper);
        console2.log("- Cantina role granted to:", config.cantinaOperator);
        console2.log("- Asset will be set when strategy is linked");
        
        return router;
    }
    
    /**
     * @notice Deploy factory or use existing one
     */
    function deployOrGetFactory(DeploymentConfig memory config, address donationAddress) internal returns (YieldDonatingStrategyFactory) {
        // Check if factory address is provided in environment
        address existingFactory = vm.envOr("FACTORY_ADDRESS", address(0));
        
        if (existingFactory != address(0)) {
            console2.log("Using existing factory at:", existingFactory);
            YieldDonatingStrategyFactory factoryInstance = YieldDonatingStrategyFactory(existingFactory);
            console2.log("- Management:", factoryInstance.management());
            console2.log("- Donation Address:", factoryInstance.donationAddress());
            console2.log("- Keeper:", factoryInstance.keeper());
            console2.log("- Emergency Admin:", factoryInstance.EMERGENCY_ADMIN());
            return factoryInstance;
        }
        
        // Deploy new factory
        console2.log("Deploying new factory...");
        YieldDonatingStrategyFactory newFactory = new YieldDonatingStrategyFactory(
            config.management,      // management
            donationAddress,        // donationAddress (SecurityRouter)
            config.keeper,          // keeper
            config.emergencyAdmin   // emergencyAdmin
        );
        
        console2.log("Factory deployed at:", address(newFactory));
        console2.log("- Management:", newFactory.management());
        console2.log("- Donation Address (SecurityRouter):", newFactory.donationAddress());
        console2.log("- Keeper:", newFactory.keeper());
        console2.log("- Emergency Admin:", newFactory.EMERGENCY_ADMIN());
        console2.log("- TokenizedStrategy implementation:", newFactory.TOKENIZED_STRATEGY_ADDRESS());
        console2.log("- Enable Burning:", newFactory.enableBurning());
        
        return newFactory;
    }
    
    /**
     * @notice Deploy strategy using factory
     */
    function deployStrategyWithFactory(DeploymentConfig memory config) internal returns (address) {
        console2.log("Deploying strategy with factory...");
        console2.log("- Yield Source (Spark Vault):", SPARK_VAULT);
        console2.log("- Asset (USDC):", USDC);
        console2.log("- Name:", config.strategyName);
        
        address deployedStrategy = factory.newStrategy(
            SPARK_VAULT,           // yieldSource
            USDC,                  // asset
            config.strategyName    // name
        );
        
        console2.log("Strategy deployed at:", deployedStrategy);
        console2.log("- Factory deployment tracked:", factory.isDeployedStrategy(deployedStrategy));
        
        return deployedStrategy;
    }
    
    /**
     * @notice Link contracts by setting strategy address in SecurityRouter
     */
    function linkContracts(DeploymentConfig memory config) internal {
        vm.prank(config.admin);
        securityRouter.setStrategy(strategy);
        
        console2.log("Contracts linked successfully");
        console2.log("- SecurityRouter.YIELD_STRATEGY:", address(securityRouter.YIELD_STRATEGY()));
        
        // Verify the link
        require(
            address(securityRouter.YIELD_STRATEGY()) == strategy,
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
        
        console2.log("Verifying Factory...");
        
        // Verify Factory configuration
        require(factory.management() == config.management, "Wrong management in factory");
        require(factory.donationAddress() == address(securityRouter), "Wrong donation address in factory");
        require(factory.keeper() == config.keeper, "Wrong keeper in factory");
        require(factory.EMERGENCY_ADMIN() == config.emergencyAdmin, "Wrong emergency admin in factory");
        
        console2.log("Verifying Strategy...");
        
        // Verify Strategy is tracked by factory
        require(factory.isDeployedStrategy(strategy), "Strategy not registered in factory");
        
        // Verify Strategy configuration (using interface)
        IStrategyInterface strategyInterface = IStrategyInterface(strategy);
        require(strategyInterface.asset() == USDC, "Wrong asset in strategy");
        
        console2.log("Verifying contract linking...");
        
        // Verify contracts are linked
        require(address(securityRouter.YIELD_STRATEGY()) == strategy, "Contracts not linked");
        
        console2.log("++ All verifications passed!");
    }
    
    /**
     * @notice Print deployment summary with all important information
     */
    function printDeploymentSummary(DeploymentConfig memory config) internal view {
        console2.log("\n++ DEPLOYMENT SUMMARY");
        console2.log("=====================");
        
        console2.log("\n++ DEPLOYED CONTRACTS:");
        console2.log("SecurityRouter:        ", address(securityRouter));
        console2.log("Factory:               ", address(factory));
        console2.log("Strategy:             ", strategy);
        
        console2.log("\n++ ROLE ASSIGNMENTS:");
        console2.log("Admin:           ", config.admin);
        console2.log("Keeper:          ", config.keeper);
        console2.log("Management:      ", config.management);
        console2.log("Emergency Admin: ", config.emergencyAdmin);
        console2.log("Cantina Operator:", config.cantinaOperator);
        
        console2.log("\n++ CONFIGURATION:");
        console2.log("Strategy Name:   ", config.strategyName);
        console2.log("USDC Asset:     ", USDC);
        console2.log("Spark Vault:    ", SPARK_VAULT);
        console2.log("Burning Enabled: ", factory.enableBurning() ? "Yes" : "No");
        
        console2.log("\n++ FACTORY INFO:");
        console2.log("TokenizedStrategy Implementation:", factory.TOKENIZED_STRATEGY_ADDRESS());
        console2.log("Strategy Deployed: ", factory.isDeployedStrategy(strategy) ? "Yes" : "No");
        
        console2.log("\n++ NEXT STEPS:");
        console2.log("1. Initialize first epoch: securityRouter.advanceEpoch()");
        console2.log("2. Test small deposit: strategy.deposit(1000000, user) // 1 USDC");
        console2.log("3. Register test project: securityRouter.registerProject()");
        console2.log("4. Set up keeper bot for automated epoch management");
        console2.log("5. Configure monitoring and alerting");
        
        console2.log("\n++ IMPORTANT NOTES:");
        console2.log("- Save all contract addresses for future reference");
        console2.log("- Test with small amounts before full deployment");
        console2.log("- Set up proper monitoring for keeper operations");
        console2.log("- Ensure Cantina has the correct operator address");
        
        console2.log("\n++ SAVE THESE ADDRESSES:");
        console2.log("FACTORY_ADDRESS=", address(factory));
        console2.log("STRATEGY_ADDRESS=", strategy);
        console2.log("SECURITY_ROUTER_ADDRESS=", address(securityRouter));
    }
    
    /**
     * @notice Get deployment configuration from environment
     */
    function getDeploymentConfig() internal returns (DeploymentConfig memory) {
        // Try to get from environment variables
        address admin = vm.envOr("ADMIN_ADDRESS", address(0));
        address keeper = vm.envOr("KEEPER_ADDRESS", address(0));
        address management = vm.envOr("MANAGEMENT_ADDRESS", address(0));
        address emergencyAdmin = vm.envOr("EMERGENCY_ADMIN_ADDRESS", address(0));
        address cantinaOperator = vm.envOr("CANTINA_OPERATOR_ADDRESS", address(0));
        
        // If not set in env, use default test addresses (WARNING: NOT FOR PRODUCTION)
        if (admin == address(0)) {
            console2.log("WARNING: Using default test addresses. Set environment variables for production!");
            
            return DeploymentConfig({
                admin: 0x1234567890123456789012345678901234567890,           // TODO: Replace
                keeper: 0x2345678901234567890123456789012345678901,          // TODO: Replace
                management: 0x3456789012345678901234567890123456789012,      // TODO: Replace
                emergencyAdmin: 0x4567890123456789012345678901234567890123,    // TODO: Replace
                cantinaOperator: 0x5678901234567890123456789012345678901234,   // TODO: Replace
                strategyName: "USDC Spark YieldDonating Strategy"
            });
        }
        
        // Get strategy name from environment or use default
        string memory strategyName;
        try vm.envString("STRATEGY_NAME") returns (string memory name) {
            strategyName = name;
        } catch {
            strategyName = "USDC Spark YieldDonating Strategy";
        }
        
        return DeploymentConfig({
            admin: admin,
            keeper: keeper,
            management: management,
            emergencyAdmin: emergencyAdmin,
            cantinaOperator: cantinaOperator,
            strategyName: strategyName
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
        
        // Ensure no role conflicts
        require(config.admin != config.keeper, "Admin and keeper should be different");
        require(config.admin != config.emergencyAdmin, "Admin and emergency admin should be different");
    }
}

// Interface for strategy verification
interface IStrategyInterface {
    function asset() external view returns (address);
}
