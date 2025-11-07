// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {console2} from "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, IERC20Metadata, IStrategyInterface, ITokenizedStrategy} from "./YieldDonatingSetup.sol";

contract YieldDonatingSecurityRouterTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_securityRouterSetup() public {
        // Verify SecurityRouter is properly deployed and configured
        assertEq(address(securityRouter.YIELD_STRATEGY()), address(strategy), "Strategy not set correctly");
        assertEq(address(securityRouter.ASSET()), address(asset), "Asset not set correctly");
        
        // Verify dragonRouter is SecurityRouter
        assertEq(ITokenizedStrategy(address(strategy)).dragonRouter(), address(securityRouter), "DragonRouter not set correctly");
        
        console2.log("SecurityRouter address:", address(securityRouter));
        console2.log("Strategy address:", address(strategy));
        console2.log("Asset address:", address(asset));
    }

    function test_profitableReportWithSecurityRouter(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint256 _timeInDays = 30; // Fixed 30 days

        // Check initial SecurityRouter balances
        checkSecurityRouterBalances(0, 0, "Initial state");

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Move forward in time to simulate yield accrual period
        uint256 timeElapsed = _timeInDays * 1 days;
        skip(timeElapsed);

        // Trigger report directly on strategy (keeper calls it)
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();

        // Check return values - should have profit equal to simulated yield
        assertGt(profit, 0, "!profit should be greater than 0");
        assertEq(loss, 0, "!loss should be 0");

        // Check that profit was minted to SecurityRouter
        uint256 routerShares = securityRouter.getAccumulatedShares();
        uint256 routerAssets = securityRouter.getAccumulatedAssetValue();
        
        assertGt(routerShares, 0, "!SecurityRouter should have shares");
        assertGt(routerAssets, 0, "!SecurityRouter should have asset value");
        assertEq(routerAssets, profit, "!SecurityRouter assets should equal profit");

        console2.log("Profit detected:", profit);
        console2.log("SecurityRouter shares:", routerShares);
        console2.log("SecurityRouter asset value:", routerAssets);

        // Verify user can still withdraw their principal
        uint256 balanceBefore = asset.balanceOf(user);
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // SecurityRouter should still have the profit shares
        assertGt(securityRouter.getAccumulatedShares(), 0, "!SecurityRouter should keep profit shares");
    }

    function test_epochAdvanceWithSecurityRouter(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10); // Smaller amount for faster test
        
        // Setup: Deposit and generate profit
        mintAndDepositIntoStrategy(strategy, user, _amount);
        skip(30 days); // Generate yield
        
        // Trigger report to mint profit shares to SecurityRouter
        vm.prank(keeper);
        (uint256 profit,) = ITokenizedStrategy(address(strategy)).report();
        assertGt(profit, 0, "Should have profit");
        
        uint256 sharesBefore = securityRouter.getAccumulatedShares();
        uint256 assetsBefore = asset.balanceOf(address(securityRouter));
        
        assertGt(sharesBefore, 0, "SecurityRouter should have shares before epoch advance");
        assertEq(assetsBefore, 0, "SecurityRouter should have no assets before epoch advance");

        // Advance epoch - this should redeem shares for assets
        skip(30 days); // Move to next epoch
        advanceEpoch();

        uint256 sharesAfter = securityRouter.getAccumulatedShares();
        uint256 assetsAfter = asset.balanceOf(address(securityRouter));
        
        assertEq(sharesAfter, 0, "SecurityRouter should have no shares after epoch advance");
        assertGt(assetsAfter, 0, "SecurityRouter should have assets after epoch advance");
        assertEq(assetsAfter, profit, "Assets should equal the profit amount");

        console2.log("Shares before epoch advance:", sharesBefore);
        console2.log("Assets after epoch advance:", assetsAfter);
        console2.log("Profit amount:", profit);
    }

    function test_projectRegistrationAndApproval() public {
        // Register a project
        uint256 projectId = registerProject("Test Project", "https://test.com/metadata");
        assertEq(projectId, 1, "First project should have ID 1");
        
        // Check project details
        (string memory name, string memory metadata, address owner, uint256 registeredEpoch, uint256 approvedEpoch) = 
            securityRouter.projects(projectId);
        
        assertEq(name, "Test Project", "Project name mismatch");
        assertEq(metadata, "https://test.com/metadata", "Project metadata mismatch");
        assertEq(owner, address(this), "Project owner mismatch");
        assertEq(registeredEpoch, 1, "Project registered epoch mismatch");
        assertEq(approvedEpoch, 0, "Project should not be approved yet");

        // Approve the project
        approveProject(projectId);
        
        // Check approval
        (, , , , approvedEpoch) = securityRouter.projects(projectId);
        assertEq(approvedEpoch, 1, "Project should be approved in current epoch");

        console2.log("Project registered with ID:", projectId);
        console2.log("Project approved in epoch:", approvedEpoch);
    }
}
