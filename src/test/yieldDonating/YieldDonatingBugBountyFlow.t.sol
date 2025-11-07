// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {console2} from "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, IERC20Metadata, IStrategyInterface, ITokenizedStrategy} from "./YieldDonatingSetup.sol";
import {SecurityRouter} from "../../router/SecurityRouter.sol";

contract YieldDonatingBugBountyFlowTest is Setup {
    // Test addresses for reporters
    address reporter1 = address(0x1001);
    address reporter2 = address(0x1002);
    address reporter3 = address(0x1003);
    
    // Project IDs
    uint256 project1Id;
    uint256 project2Id;
    
    // Private key for signing (corresponds to cantinaOperator)
    uint256 cantinaPrivateKey = 0x6666;
    
    // Reward tracking variables (to avoid stack too deep)
    uint256 reporter1Reward;
    uint256 reporter2Reward;
    uint256 reporter3Reward;

    function setUp() public virtual override {
        // Override cantinaOperator to use address from our private key
        cantinaOperator = vm.addr(cantinaPrivateKey);
        
        super.setUp();
        
        // Label test addresses
        vm.label(reporter1, "reporter1");
        vm.label(reporter2, "reporter2");
        vm.label(reporter3, "reporter3");
    }
    
    function createCantinaSignature(
        uint256 epoch,
        SecurityRouter.ProjectReportSubmission[] memory projectReports
    ) internal view returns (bytes memory) {
        // Encode the data the same way the contract does
        bytes memory encoded = abi.encode(epoch, projectReports);
        bytes32 messageHash;
        assembly {
            messageHash := keccak256(add(encoded, 0x20), mload(encoded))
        }
        
        // Create the Ethereum signed message hash
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Sign with the cantina private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cantinaPrivateKey, ethSignedHash);
        
        return abi.encodePacked(r, s, v);
    }
    
    function _checkBalancesAndSubmitReports(
        uint256 epoch,
        SecurityRouter.ProjectReportSubmission[] memory projectReports,
        bytes memory signature
    ) internal {
        // Check balances BEFORE submission
        console2.log("Balances BEFORE bug report submission:");
        uint256 reporter1Before = asset.balanceOf(reporter1);
        uint256 reporter2Before = asset.balanceOf(reporter2);
        uint256 reporter3Before = asset.balanceOf(reporter3);
        console2.log("  Reporter 1:", reporter1Before);
        console2.log("  Reporter 2:", reporter2Before);
        console2.log("  Reporter 3:", reporter3Before);
        
        vm.prank(cantinaOperator);
        securityRouter.submitBugReports(epoch, projectReports, signature);
        
        console2.log("All bug reports submitted");
        
        // Check balances AFTER submission
        console2.log("Balances AFTER bug report submission:");
        uint256 reporter1After = asset.balanceOf(reporter1);
        uint256 reporter2After = asset.balanceOf(reporter2);
        uint256 reporter3After = asset.balanceOf(reporter3);
        console2.log("  Reporter 1:", reporter1After);
        console2.log("  Reporter 2:", reporter2After);
        console2.log("  Reporter 3:", reporter3After);
        
        // Calculate rewards
        reporter1Reward = reporter1After - reporter1Before;
        reporter2Reward = reporter2After - reporter2Before;
        reporter3Reward = reporter3After - reporter3Before;
        
        console2.log("Rewards received:");
        console2.log("  Reporter 1 reward:", reporter1Reward);
        console2.log("  Reporter 2 reward:", reporter2Reward);
        console2.log("  Reporter 3 reward:", reporter3Reward);
    }

    function test_completeBugBountyFlow() public {
        uint256 depositAmount = 1000000; // 1 USDC (6 decimals)
        
        console2.log("=== PHASE 1: SETUP AND DEPOSIT ===");
        
        // Step 1: Deposit into strategy to generate yield
        mintAndDepositIntoStrategy(strategy, user, depositAmount);
        console2.log("Deposited:", depositAmount);
        console2.log("Strategy total assets:", strategy.totalAssets());
        
        // Step 2: Register two projects
        console2.log("\n=== PHASE 2: PROJECT REGISTRATION ===");
        
        project1Id = registerProject("DeFi Protocol Alpha", "https://alpha.defi/metadata");
        project2Id = registerProject("NFT Marketplace Beta", "https://beta.nft/metadata");
        
        console2.log("Project 1 ID:", project1Id);
        console2.log("Project 2 ID:", project2Id);
        
        // Step 3: Cantina approves both projects (must be done before yield generation)
        console2.log("\n=== PHASE 3: PROJECT APPROVAL ===");
        
        approveProject(project1Id);
        approveProject(project2Id);
        
        console2.log("Both projects approved by Cantina");
        console2.log("Current epoch after approval:", securityRouter.currentEpoch());
        
        // Step 4: Generate yield by waiting and triggering report
        console2.log("\n=== PHASE 4: YIELD GENERATION ===");
        
        skip(30 days); // Generate yield over time
        
        // Trigger strategy report to mint profit shares to SecurityRouter
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(address(strategy)).report();
        
        console2.log("Profit generated:", profit);
        console2.log("Loss:", loss);
        
        uint256 routerShares = securityRouter.getAccumulatedShares();
        uint256 routerAssetValue = securityRouter.getAccumulatedAssetValue();
        
        console2.log("SecurityRouter shares:", routerShares);
        console2.log("SecurityRouter asset value:", routerAssetValue);
        
        // Step 5: Advance epoch to convert shares to assets
        console2.log("\n=== PHASE 5: EPOCH ADVANCEMENT ===");
        
        skip(30 days); // Move to next epoch
        advanceEpoch();
        
        uint256 routerBalance = asset.balanceOf(address(securityRouter));
        console2.log("SecurityRouter USDC balance after epoch advance:", routerBalance);
        
        // Verify we have funds for distribution
        assertGt(routerBalance, 0, "SecurityRouter should have USDC for rewards");
        
        // Step 6: Submit bug reports for both projects
        console2.log("\n=== PHASE 6: BUG REPORT SUBMISSION ===");
        
        // Create bug reports array
        // Project 1: 2 reporters
        // - Reporter 1: 1 Critical bug
        // - Reporter 2: 2 Medium bugs
        // Project 2: 1 reporter
        // - Reporter 3: 1 Low + 1 Informational bug
        
        uint256 currentEpoch = securityRouter.currentEpoch() - 1; // Previous epoch where we have funds
        console2.log("Submitting reports for epoch:", currentEpoch);
        console2.log("Current epoch:", securityRouter.currentEpoch());
        
        // Check project approval epochs
        (, , , , uint256 project1ApprovalEpoch) = securityRouter.projects(project1Id);
        (, , , , uint256 project2ApprovalEpoch) = securityRouter.projects(project2Id);
        console2.log("Project 1 approved in epoch:", project1ApprovalEpoch);
        console2.log("Project 2 approved in epoch:", project2ApprovalEpoch);
        
        // Check epoch data
        (uint256 totalYield, uint256 totalProjects, uint256 distributedAmount, bool finalized) = securityRouter.epochs(currentEpoch);
        console2.log("Epoch", currentEpoch, "data:");
        console2.log("  Total yield:", totalYield);
        console2.log("  Total projects:", totalProjects);
        console2.log("  Distributed amount:", distributedAmount);
        console2.log("  Finalized:", finalized);
        
        // Prepare bug reports for Project 1
        SecurityRouter.BugReportSubmission[] memory project1Reports = new SecurityRouter.BugReportSubmission[](2);
        
        // Reporter 1: Critical bug
        project1Reports[0] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("report1"),
            reporter: reporter1,
            severity: SecurityRouter.Severity.CRITICAL
        });
        
        // Reporter 2: Medium bugs (we'll submit 2 separate reports)
        project1Reports[1] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("report2"),
            reporter: reporter2,
            severity: SecurityRouter.Severity.MEDIUM
        });
        
        // Prepare bug reports for Project 2
        SecurityRouter.BugReportSubmission[] memory project2Reports = new SecurityRouter.BugReportSubmission[](2);
        
        // Reporter 3: Low and Informational bugs
        project2Reports[0] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("report3"),
            reporter: reporter3,
            severity: SecurityRouter.Severity.LOW
        });
        
        project2Reports[1] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("report4"),
            reporter: reporter3,
            severity: SecurityRouter.Severity.INFORMATIONAL
        });
        
        // Combine all reports into ProjectReportSubmission format
        SecurityRouter.ProjectReportSubmission[] memory projectReports = new SecurityRouter.ProjectReportSubmission[](2);
        
        // Add second medium report for reporter2 to project1Reports
        SecurityRouter.BugReportSubmission[] memory project1AllReports = new SecurityRouter.BugReportSubmission[](3);
        project1AllReports[0] = project1Reports[0]; // Critical
        project1AllReports[1] = project1Reports[1]; // Medium 1
        project1AllReports[2] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("report2b"),
            reporter: reporter2,
            severity: SecurityRouter.Severity.MEDIUM
        }); // Medium 2
        
        projectReports[0] = SecurityRouter.ProjectReportSubmission({
            projectId: project1Id,
            reports: project1AllReports
        });
        
        projectReports[1] = SecurityRouter.ProjectReportSubmission({
            projectId: project2Id,
            reports: project2Reports
        });
        
        // Create a proper signature using the cantina private key
        bytes memory signature = createCantinaSignature(currentEpoch, projectReports);
        
        // Submit all reports at once
        console2.log("Submitting all bug reports...");
        console2.log("Reporter addresses in reports:");
        console2.log("  Reporter 1:", project1AllReports[0].reporter);
        console2.log("  Reporter 2:", project1AllReports[1].reporter);
        console2.log("  Reporter 2 (2nd):", project1AllReports[2].reporter);
        console2.log("  Reporter 3 (low):", project2Reports[0].reporter);
        console2.log("  Reporter 3 (info):", project2Reports[1].reporter);
        
        // Check balances and submit reports
        _checkBalancesAndSubmitReports(currentEpoch, projectReports, signature);
        
        // Check epoch data after submission
        (totalYield, totalProjects, distributedAmount, finalized) = securityRouter.epochs(currentEpoch);
        console2.log("After submission - Epoch", currentEpoch, "data:");
        console2.log("  Total yield:", totalYield);
        console2.log("  Total projects:", totalProjects);
        console2.log("  Distributed amount:", distributedAmount);
        console2.log("  Finalized:", finalized);
        
        // Step 8: Final verification
        console2.log("\n=== PHASE 8: FINAL VERIFICATION ===");
        
        uint256 routerBalanceAfter = asset.balanceOf(address(securityRouter));
        console2.log("SecurityRouter balance after distribution:", routerBalanceAfter);
        
        console2.log("\n=== REWARD SUMMARY ===");
        console2.log("Reporter 1 reward (1 Critical):", reporter1Reward);
        console2.log("Reporter 2 reward (2 Medium):", reporter2Reward);
        console2.log("Reporter 3 reward (1 Low + 1 Info):", reporter3Reward);
        
        uint256 totalRewardsDistributed = reporter1Reward + reporter2Reward + reporter3Reward;
        console2.log("Total rewards distributed:", totalRewardsDistributed);
        console2.log("Funds remaining in router:", routerBalanceAfter);
        
        // Verify that rewards were actually distributed
        assertGt(reporter1Reward, 0, "Reporter 1 should receive reward for critical bug");
        assertGt(reporter2Reward, 0, "Reporter 2 should receive reward for medium bugs");
        assertGt(reporter3Reward, 0, "Reporter 3 should receive reward for low/info bugs");
        
        // Verify reward hierarchy (Critical > Medium > Low > Informational)
        // Reporter 1 (1 Critical) should get more than Reporter 2 (2 Medium) per bug
        // But Reporter 2 might get more total due to having 2 bugs
        console2.log("Critical bug reward rate:", reporter1Reward);
        console2.log("Medium bug reward rate:", reporter2Reward / 2);
        
        // Verify that funds were distributed (router balance should be low)
        assertLt(routerBalanceAfter, 100, "Most funds should have been distributed");
        
        console2.log("\n=== TEST COMPLETED SUCCESSFULLY ===");
        console2.log("+ Projects registered and approved");
        console2.log("+ Yield generated and collected");
        console2.log("+ Bug reports submitted with different severities");
        console2.log("+ Rewards distributed to reporters");
        console2.log("+ All assertions passed");
    }
    
    function test_rewardCalculationDetails() public {
        // This test focuses on the reward calculation mechanics
        uint256 depositAmount = 10000000; // 10 USDC for more significant rewards
        
        // Setup: deposit
        mintAndDepositIntoStrategy(strategy, user, depositAmount);
        
        // Register and approve a project BEFORE generating yield
        uint256 projectId = registerProject("Test Project", "metadata");
        approveProject(projectId);
        
        // Generate yield and advance epoch
        skip(30 days);
        
        vm.prank(keeper);
        ITokenizedStrategy(address(strategy)).report();
        
        skip(30 days);
        advanceEpoch();
        
        uint256 availableFunds = asset.balanceOf(address(securityRouter));
        console2.log("Available funds for distribution:", availableFunds);
        
        uint256 currentEpoch = securityRouter.currentEpoch() - 1;
        
        // Submit one bug of each severity to see the reward structure
        SecurityRouter.BugReportSubmission[] memory reports = new SecurityRouter.BugReportSubmission[](4);
        
        reports[0] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("critical"),
            reporter: reporter1,
            severity: SecurityRouter.Severity.CRITICAL
        });
        
        reports[1] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("medium"),
            reporter: reporter2,
            severity: SecurityRouter.Severity.MEDIUM
        });
        
        reports[2] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("low"),
            reporter: reporter3,
            severity: SecurityRouter.Severity.LOW
        });
        
        reports[3] = SecurityRouter.BugReportSubmission({
            reportId: keccak256("info"),
            reporter: address(0x1004),
            severity: SecurityRouter.Severity.INFORMATIONAL
        });
        
        // Record balances before
        uint256[] memory balancesBefore = new uint256[](4);
        balancesBefore[0] = asset.balanceOf(reporter1);
        balancesBefore[1] = asset.balanceOf(reporter2);
        balancesBefore[2] = asset.balanceOf(reporter3);
        balancesBefore[3] = asset.balanceOf(address(0x1004));
        
        // Create ProjectReportSubmission
        SecurityRouter.ProjectReportSubmission[] memory projectReports = new SecurityRouter.ProjectReportSubmission[](1);
        projectReports[0] = SecurityRouter.ProjectReportSubmission({
            projectId: projectId,
            reports: reports
        });
        
        // Create proper signature
        bytes memory signature = createCantinaSignature(currentEpoch, projectReports);
        
        // Submit reports
        vm.prank(cantinaOperator);
        securityRouter.submitBugReports(currentEpoch, projectReports, signature);
        
        // Record balances after
        uint256[] memory balancesAfter = new uint256[](4);
        balancesAfter[0] = asset.balanceOf(reporter1);
        balancesAfter[1] = asset.balanceOf(reporter2);
        balancesAfter[2] = asset.balanceOf(reporter3);
        balancesAfter[3] = asset.balanceOf(address(0x1004));
        
        // Calculate and display rewards
        console2.log("\n=== REWARD BREAKDOWN BY SEVERITY ===");
        console2.log("Critical reward:", balancesAfter[0] - balancesBefore[0]);
        console2.log("Medium reward:", balancesAfter[1] - balancesBefore[1]);
        console2.log("Low reward:", balancesAfter[2] - balancesBefore[2]);
        console2.log("Informational reward:", balancesAfter[3] - balancesBefore[3]);
        
        // Verify reward hierarchy
        uint256 criticalReward = balancesAfter[0] - balancesBefore[0];
        uint256 mediumReward = balancesAfter[1] - balancesBefore[1];
        uint256 lowReward = balancesAfter[2] - balancesBefore[2];
        uint256 infoReward = balancesAfter[3] - balancesBefore[3];
        
        assertGt(criticalReward, mediumReward, "Critical should pay more than Medium");
        assertGt(mediumReward, lowReward, "Medium should pay more than Low");
        assertEq(lowReward, infoReward, "Low and Informational should have same payout (both weight 1)");
    }
}
