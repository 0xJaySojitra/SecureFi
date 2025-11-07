// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {YieldDonatingStrategy as Strategy} from "../../strategies/yieldDonating/YieldDonatingStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {YieldDonatingStrategyFactory as StrategyFactory} from "../../strategies/yieldDonating/YieldDonatingStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {SecurityRouter} from "../../router/SecurityRouter.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract YieldDonatingSetup is Test, IEvents {
    // Contract instances that we will use repeatedly.
    IERC20Metadata public asset;
    IStrategyInterface public strategy;
    SecurityRouter public securityRouter;

    StrategyFactory public strategyFactory;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public dragonRouter; // Will be set to SecurityRouter address
    address public emergencyAdmin = address(5);
    
    // SecurityRouter specific addresses
    address public cantinaOperator = address(6);
    address public admin = address(7);

    // YieldDonating specific variables
    bool public enableBurning = true;
    address public tokenizedStrategyAddress;
    address public yieldSource;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public maxBps = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1,000,000 of the asset
    uint256 public maxFuzzAmount;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        // Read asset address from environment
        address testAssetAddress = vm.envAddress("TEST_ASSET_ADDRESS");
        require(testAssetAddress != address(0), "TEST_ASSET_ADDRESS not set in .env");

        // Set asset
        asset = IERC20Metadata(testAssetAddress);

        // Set decimals
        decimals = asset.decimals();

        // Set max fuzz amount to 1,000,000 of the asset
        maxFuzzAmount = 1_000_000 * 10 ** decimals;

        // Read yield source from environment
        yieldSource = vm.envAddress("TEST_YIELD_SOURCE");
        require(yieldSource != address(0), "TEST_YIELD_SOURCE not set in .env");

        // Deploy YieldDonatingTokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldDonatingTokenizedStrategy());

        // Step 1: Deploy SecurityRouter first (without strategy)
        securityRouter = new SecurityRouter(
            cantinaOperator,
            admin,
            keeper
        );

        // Step 2: Set dragonRouter to SecurityRouter address
        dragonRouter = address(securityRouter);
        strategyFactory = new StrategyFactory(management, dragonRouter, keeper, emergencyAdmin);
        
        // Step 3: Deploy strategy with SecurityRouter as dragonRouter
        strategy = IStrategyInterface(setUpStrategy());

        // Step 4: Set the strategy address in SecurityRouter
        vm.prank(admin);
        securityRouter.setStrategy(address(strategy));

        // Note: SecurityRouter doesn't need keeper role on strategy
        // The keeper will call SecurityRouter functions, and SecurityRouter will call strategy functions
        // This maintains the original keeper setup for existing tests

        // factory = strategy.FACTORY(); // Remove this line as FACTORY is not implemented

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(address(securityRouter), "securityRouter");
        vm.label(cantinaOperator, "cantinaOperator");
        vm.label(admin, "admin");
        vm.label(user, "user");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new Strategy(
                    yieldSource,
                    address(asset),
                    "YieldDonating Strategy",
                    management,
                    keeper,
                    emergencyAdmin,
                    dragonRouter, // Use dragonRouter as the donation address
                    enableBurning,
                    tokenizedStrategyAddress
                )
            )
        );

        // The strategy should already have management set correctly during construction
        // No need to call acceptManagement as there's no pending management

        return address(_strategy);
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = IERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(IERC20Metadata _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setDragonRouter(address _newDragonRouter) public {
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(_newDragonRouter);

        // Fast forward to bypass cooldown
        skip(7 days);

        // Anyone can finalize after cooldown
        ITokenizedStrategy(address(strategy)).finalizeDragonRouterChange();
    }

    function setEnableBurning(bool _enableBurning) public {
        vm.prank(management);
        // Call using low-level call since setEnableBurning may not be in all interfaces
        (bool success, ) = address(strategy).call(abi.encodeWithSignature("setEnableBurning(bool)", _enableBurning));
        require(success, "setEnableBurning failed");
    }

    // ============ SECURITY ROUTER HELPER FUNCTIONS ============

    function checkSecurityRouterBalances(
        uint256 expectedShares,
        uint256 expectedAssets,
        string memory message
    ) public {
        uint256 actualShares = securityRouter.getAccumulatedShares();
        uint256 actualAssets = securityRouter.getAccumulatedAssetValue();
        
        assertEq(actualShares, expectedShares, string(abi.encodePacked(message, " - shares")));
        assertEq(actualAssets, expectedAssets, string(abi.encodePacked(message, " - assets")));
    }

    function advanceEpoch() public {
        vm.prank(keeper);
        securityRouter.advanceEpoch();
    }

    function triggerReportDirect() public returns (uint256 profit, uint256 loss) {
        // Call report directly on strategy (alternative method)
        vm.prank(keeper);
        return ITokenizedStrategy(address(strategy)).report();
    }

    function registerProject(string memory name, string memory metadata) public returns (uint256) {
        return securityRouter.registerProject(name, metadata);
    }

    function approveProject(uint256 projectId) public {
        vm.prank(cantinaOperator);
        securityRouter.approveProject(projectId);
    }
}
