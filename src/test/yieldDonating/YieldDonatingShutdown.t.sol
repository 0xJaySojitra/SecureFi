pragma solidity ^0.8.18;

import {YieldDonatingSetup as Setup} from "./YieldDonatingSetup.sol";
import {console2} from "forge-std/console2.sol";

contract YieldDonatingShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_emergencyWithdraw_maxUint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        // console2.log("test_emergencyWithdraw_maxUint", _amount);
        // console2.log("user withdraw limit before deposit", strategy.maxWithdraw(user));
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        console2.log("strategy.totalAssets", strategy.totalAssets());
        console2.log("user withdraw limit after deposit", strategy.maxWithdraw(user));
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);
        console2.log("strategy.totalAssets after skip", strategy.totalAssets());
        console2.log("user withdraw limit after skip", strategy.maxWithdraw(user));
        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        console2.log("sstrategy.totalAssets() and _amount", strategy.totalAssets(), _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        console2.log("asset balance of strategy", asset.balanceOf(address(strategy)));

        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);
        
        console2.log("asset balance of strategy after emergencyWithdraw", asset.balanceOf(address(strategy)));
        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);
        console2.log("balanceBefore", balanceBefore);
        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console2.log("asset balance of strategy before redeem", asset.balanceOf(address(strategy)));

        console2.log("asset.balanceOf(user) after redeem", asset.balanceOf(user));
        console2.log("balanceBefore + _amount", balanceBefore + _amount);
        console2.log("asset balance of strategy after redeem", asset.balanceOf(address(strategy)));

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }
}
