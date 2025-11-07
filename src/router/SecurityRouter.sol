// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Interface for interacting with the YieldDonatingStrategy (ERC4626-compliant)
 * @dev The strategy is both an ERC4626 vault and an ERC20 token (shares)
 */
interface IERC4626Strategy {
    // ERC4626 functions
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    
    // ERC20 functions (for share balance)
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    
    // Strategy-specific functions
    function report() external returns (uint256 profit, uint256 loss);
}

/**
 * @title SecurityRouter
 * @notice Dragon Router contract for Octant v2 that receives donated yield shares
 *         and distributes them as bug bounty rewards to security researchers via Cantina
 * @dev This contract acts as the "dragonRouter" in the YieldDonatingStrategy system.
 *      It receives minted shares when strategy reports profits and redeems them for
 *      underlying assets to distribute as bug bounty rewards.
 */
contract SecurityRouter is AccessControl {
    using SafeERC20 for IERC20;
    
    // ============ STATE VARIABLES ============
    
    bytes32 public constant CANTINA_ROLE = keccak256("CANTINA_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    
    /// @notice The YieldDonatingStrategy contract (ERC4626-compliant)
    /// @dev This is the strategy that mints donation shares to this router
    IERC4626Strategy public YIELD_STRATEGY;
    
    /// @notice The underlying asset (e.g., USDC)
    IERC20Metadata public ASSET;
    
    uint256 public constant EPOCH_DURATION = 30 days;
    uint256 public constant TOTAL_CAP_PERCENTAGE = 2500; // 25% in basis points (25% = 2500/10000)
    uint256 public constant MAX_ISSUE_PERCENTAGE = 500; // 5% in basis points (5% = 500/10000)
    uint256 public epochStartTime;
    uint256 public currentEpoch;
    uint256 public totalAvailableFunds; // Accumulated funds including rollovers
    
    // ============ STRUCTS ============
    
    struct Project {
        string name;
        string metadata;
        address owner;
        uint256 registeredEpoch;
        uint256 approvedEpoch; // The epoch in which the project was approved (0 if not approved)
    }
    
    struct BugReport {
        bytes32 reportId;
        address reporter;
        Severity severity;
        bool paid;
        uint256 amount;
    }
    
    enum Severity {
        INFORMATIONAL,
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }
    
    struct EpochData {
        uint256 totalYield;
        uint256 totalProjects;
        uint256 distributedAmount;
        uint256 rolloverAmount; // Amount carried over from previous epochs
        bool finalized;
    }
    
    // ============ MAPPINGS ============
    
    mapping(uint256 => Project) public projects; // projectId => Project
    mapping(uint256 => EpochData) public epochs;
    mapping(uint256 => mapping(uint256 => BugReport[])) public epochProjectReports; 
    // epoch => projectId => BugReport[]
    
    uint256 public projectCount;
    
    // ============ STRUCTS ============
    
    /**
     * @notice Helper struct for bug report submissions from Cantina
     * @dev Used as input parameter for submitBugReports function
     */
    struct BugReportSubmission {
        bytes32 reportId;
        address reporter;
        Severity severity;
    }

    /**
     * @notice Helper struct for grouping multiple bug reports by project
     * @dev Used to submit bug reports for multiple projects in a single transaction
     */
    struct ProjectReportSubmission {
        uint256 projectId;
        BugReportSubmission[] reports;
    }
    
    // ============ EVENTS ============
    
    event ProjectRegistered(uint256 indexed projectId, string name, address owner);
    event ProjectApproved(uint256 indexed projectId);
    event EpochAdvanced(uint256 indexed newEpoch, uint256 yieldCollected);
    event BugPayoutExecuted(
        uint256 indexed epoch,
        uint256 indexed projectId,
        address indexed reporter,
        uint256 amount,
        Severity severity
    );
    event StrategySet(address indexed strategy);
    
    // ============ CONSTRUCTOR ============
    
    /**
     * @param _cantinaOperator Address of Cantina operator who can approve projects and submit reports
     * @param _admin Address of admin who can manage roles
     * @param _keeper Address of keeper who can trigger epoch advances and reports
     */
    constructor(
        address _cantinaOperator,
        address _admin,
        address _keeper
    ) {
        _grantRole(CANTINA_ROLE, _cantinaOperator);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _keeper);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        
        epochStartTime = block.timestamp;
        currentEpoch = 1;
    }

    /**
     * @notice Set the yield strategy contract address
     * @dev Can only be called by admin. Used to break circular dependency during deployment.
     * @param _yieldStrategy Address of the YieldDonatingStrategy contract
     */
    function setStrategy(address _yieldStrategy) external onlyRole(ADMIN_ROLE) {
        require(_yieldStrategy != address(0), "Invalid strategy address");
        require(address(YIELD_STRATEGY) == address(0), "Strategy already set");
        
        YIELD_STRATEGY = IERC4626Strategy(_yieldStrategy);
        ASSET = IERC20Metadata(YIELD_STRATEGY.asset());
        
        emit StrategySet(_yieldStrategy);
    }
    
    // ============ PROJECT MANAGEMENT ============
    
    function registerProject(
        string memory name,
        string memory metadata
    ) external returns (uint256) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(metadata).length > 0, "Metadata URI required");
        require(projectCount < type(uint256).max, "Too many projects");
        projectCount++;
        projects[projectCount] = Project({
            name: name,
            metadata: metadata,
            owner: msg.sender,
            registeredEpoch: currentEpoch,
            approvedEpoch: 0
        });
        emit ProjectRegistered(projectCount, name, msg.sender);
        return projectCount;
    }
    
    function approveProject(uint256 projectId) 
        external 
        onlyRole(CANTINA_ROLE) 
    {
        require(projectId > 0 && projectId <= projectCount, "Invalid projectId");
        require(projects[projectId].approvedEpoch == 0, "Already approved");
        projects[projectId].approvedEpoch = currentEpoch; // Mark the epoch in which it was approved
        emit ProjectApproved(projectId);
    }
    
    // ============ EPOCH MANAGEMENT ============
    
    /**
     * @notice Advances to the next epoch and redeems accumulated yield shares
     * @dev This function should be called by the keeper at the end of each epoch period.
     *      It triggers a report on the strategy to mint new donation shares, then redeems
     *      all accumulated shares for the underlying asset (USDC).
     * 
     * Flow:
     * 1. Keeper calls strategy.report() -> mints profit shares to this router
     * 2. Router redeems all shares -> withdraws underlying assets from Aave vault
     * 3. Assets are now available for bug bounty distribution
     */
    function advanceEpoch() external onlyRole(KEEPER_ROLE) {
        require(address(YIELD_STRATEGY) != address(0), "Strategy not set");
        require(
            block.timestamp >= epochStartTime + EPOCH_DURATION,
            "Epoch not finished"
        );
        // Step 1: Trigger strategy report to mint new donation shares
        // The keeper should have already called report() on the strategy before this,
        // but we document it here for clarity of the flow
        // Note: report() must be called externally by keeper BEFORE advanceEpoch()
        // Step 2: Redeem all accumulated strategy shares for underlying assets
        uint256 shares = YIELD_STRATEGY.balanceOf(address(this));
        uint256 yieldAmount = 0;
        if (shares > 0) {
            // Redeem shares to get underlying asset (USDC)
            // This triggers _freeFunds in the strategy, withdrawing from Aave vault
            yieldAmount = YIELD_STRATEGY.redeem(
                shares,
                address(this),  // receiver of assets
                address(this)   // owner of shares
            );
        }
        // Step 3: Calculate rollover from previous epoch
        uint256 rolloverAmount = 0;
        if (currentEpoch > 0) {
            EpochData storage prevEpoch = epochs[currentEpoch - 1];
            if (prevEpoch.totalYield + prevEpoch.rolloverAmount > prevEpoch.distributedAmount) {
                rolloverAmount = (prevEpoch.totalYield + prevEpoch.rolloverAmount) - prevEpoch.distributedAmount;
            }
        }
        
        // Step 4: Record epoch data with rollover
        uint256 approvedCount = _countApprovedProjectsForEpoch(currentEpoch);
        totalAvailableFunds = yieldAmount + rolloverAmount;

        epochs[currentEpoch] = EpochData({
            totalYield: yieldAmount,
            totalProjects: approvedCount,
            distributedAmount: 0,
            rolloverAmount: rolloverAmount,
            finalized: false
        });
        
        // Step 5: Advance epoch
        currentEpoch++;
        epochStartTime = block.timestamp;
        emit EpochAdvanced(currentEpoch, yieldAmount);
    }
    
    // ============ BUG REPORTING & PAYOUT ============
    
    /**
     * @notice Submits bug reports and distributes rewards with 5% cap per issue
     * @dev Called by Cantina after reviewing bug reports. Can submit for any approved project
     *      regardless of which epoch they were approved in. Uses current available funds pool.
     * @param projectReports Array of ProjectReportSubmission containing projectId and their respective bug reports
     * @param signature Cantina's signature verifying the report batch
     */
    function submitBugReports(
        ProjectReportSubmission[] calldata projectReports,
        bytes calldata signature
    ) external onlyRole(CANTINA_ROLE) {
        require(projectReports.length > 0, "No project reports provided");
        require(totalAvailableFunds > 0, "No funds available for distribution");
        
        // Verify signature (Cantina signs the report batch)
        _verifyCantinaSignature(projectReports, signature);
        
        // Calculate global severity weight across all projects
        uint256 globalTotalWeight = _calculateGlobalWeight(projectReports);
        require(globalTotalWeight > 0, "No valid reports globally");
        
        // Calculate 25% cap pool for proportional distribution
        uint256 totalCapPool = (totalAvailableFunds * TOTAL_CAP_PERCENTAGE) / 10000;
        
        // Calculate yield allocation per project (divide among participating projects only)
        uint256 projectYield = totalAvailableFunds / projectReports.length;
        
        // Process reports for each project
        for (uint256 p; p < projectReports.length;) {
            _processProjectReportsWithProportionalCap(
                projectReports[p], 
                projectYield, 
                totalCapPool, 
                globalTotalWeight
            );
            unchecked { ++p; }
        }
        
        // Update totalAvailableFunds after distribution
        totalAvailableFunds = ASSET.balanceOf(address(this));
    }
    
    /**
     * @dev Internal function to process bug reports with proportional cap distribution
     *      Uses hybrid approach: severity-based formula with proportional cap from 5% pool
     */
    function _processProjectReportsWithProportionalCap(
        ProjectReportSubmission calldata projectReport,
        uint256 projectYield,
        uint256 totalCapPool,
        uint256 globalTotalWeight
    ) internal {
        uint256 projectId = projectReport.projectId;
        BugReportSubmission[] calldata reports = projectReport.reports;
        
        require(projects[projectId].approvedEpoch > 0, "Project not approved");
        require(reports.length > 0, "No reports for project");
        
        // Calculate severity weights for this project
        uint256 projectTotalWeight = _calculateTotalWeight(reports);
        require(projectTotalWeight > 0, "No valid reports");
        
        // Distribute to each reporter using hybrid approach with per-issue cap
        for (uint256 i; i < reports.length;) {
            uint256 severityWeight = _getSeverityWeight(reports[i].severity);
            
            // Step 1: Calculate reward using original severity-based formula
            uint256 severityBasedPayout = (projectYield * severityWeight) / projectTotalWeight;
            
            // Step 2: Calculate proportional cap from 25% pool
            uint256 proportionalCap = (totalCapPool * severityWeight) / globalTotalWeight;
            
            // Step 3: Calculate 5% per-issue cap
            uint256 maxPerIssueCap = (totalAvailableFunds * MAX_ISSUE_PERCENTAGE) / 10000;
            
            // Step 4: Take minimum of all three: severity-based, proportional cap, and per-issue cap
            uint256 payout = severityBasedPayout;
            if (proportionalCap < payout) payout = proportionalCap;
            if (maxPerIssueCap < payout) payout = maxPerIssueCap;
            
            // Step 5: Ensure we don't exceed available funds
            uint256 currentBalance = ASSET.balanceOf(address(this));
            if (payout > currentBalance) {
                payout = currentBalance;
            }
            
            if (payout > 0) {
                // Transfer underlying asset (USDC) to reporter
                IERC20(address(ASSET)).safeTransfer(reports[i].reporter, payout);
                
                // Record bug report in current epoch
                epochProjectReports[currentEpoch - 1][projectId].push(BugReport({
                    reportId: reports[i].reportId,
                    reporter: reports[i].reporter,
                    severity: reports[i].severity,
                    paid: true,
                    amount: payout
                }));
                
                // Track distributed amount in current epoch
                epochs[currentEpoch - 1].distributedAmount += payout;
                
                emit BugPayoutExecuted(
                    currentEpoch - 1,
                    projectId,
                    reports[i].reporter,
                    payout,
                    reports[i].severity
                );
            }
            unchecked { ++i; }
        }
    }
    
    function finalizeEpoch(uint256 epoch) 
        external 
        onlyRole(CANTINA_ROLE) 
    {
        require(!epochs[epoch].finalized, "Already finalized");
        epochs[epoch].finalized = true;
    }
    
    // ============ HELPER FUNCTIONS ============
    
    function _getSeverityWeight(Severity severity) 
        internal 
        pure 
        returns (uint256) 
    {
        if (severity == Severity.CRITICAL) return 5;
        if (severity == Severity.HIGH) return 3;
        if (severity == Severity.MEDIUM) return 2;
        if (severity == Severity.LOW) return 1;
        return 1; // INFORMATIONAL
    }
    
    function _calculateTotalWeight(BugReportSubmission[] calldata reports)
        internal
        pure
        returns (uint256)
    {
        uint256 total = 0;
        for (uint256 i = 0; i < reports.length; i++) {
            total += _getSeverityWeight(reports[i].severity);
        }
        return total;
    }
    
    function _calculateGlobalWeight(ProjectReportSubmission[] calldata projectReports)
        internal
        pure
        returns (uint256)
    {
        uint256 globalTotal = 0;
        for (uint256 p = 0; p < projectReports.length; p++) {
            globalTotal += _calculateTotalWeight(projectReports[p].reports);
        }
        return globalTotal;
    }
    
    // Returns the number of projects approved for a given epoch (approvedEpoch > 0 and <= epoch)
    function _countApprovedProjectsForEpoch(uint256 epoch) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i <= projectCount; i++) {
            if (projects[i].approvedEpoch > 0 && projects[i].approvedEpoch <= epoch) {
                count++;
            }
        }
        return count;
    }
    
    function _verifyCantinaSignature(
        ProjectReportSubmission[] calldata projectReports,
        bytes calldata signature
    ) internal view {
        bytes32 messageHash;
        bytes memory encoded = abi.encode(projectReports);
        assembly {
            messageHash := keccak256(add(encoded, 0x20), mload(encoded))
        }
        
        bytes32 ethSignedHash;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "\x19Ethereum Signed Message:\n32")
            mstore(add(ptr, 28), messageHash)
            ethSignedHash := keccak256(ptr, 60)
        }
        
        address signer = _recoverSigner(ethSignedHash, signature);
        require(hasRole(CANTINA_ROLE, signer), "Invalid signature");
    }
    
    function _recoverSigner(bytes32 hash, bytes memory signature)
        internal
        pure
        returns (address)
    {
        require(signature.length == 65, "Invalid signature length");
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        return ecrecover(hash, v, r, s);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getCurrentEpochTimeRemaining() external view returns (uint256) {
        uint256 elapsed = block.timestamp - epochStartTime;
        if (elapsed >= EPOCH_DURATION) return 0;
        return EPOCH_DURATION - elapsed;
    }
    
    /**
     * @notice Get the accumulated strategy shares (donated yield) held by this router
     * @dev These shares represent the donated profits that will be redeemed for rewards
     * @return The number of strategy shares held by this router
     */
    function getAccumulatedShares() external view returns (uint256) {
        if (address(YIELD_STRATEGY) == address(0)) return 0;
        return YIELD_STRATEGY.balanceOf(address(this));
    }
    
    /**
     * @notice Get the asset value of accumulated shares
     * @dev Converts strategy shares to underlying asset amount
     * @return The asset value of shares held by this router
     */
    function getAccumulatedAssetValue() external view returns (uint256) {
        if (address(YIELD_STRATEGY) == address(0)) return 0;
        uint256 shares = YIELD_STRATEGY.balanceOf(address(this));
        if (shares == 0) return 0;
        return YIELD_STRATEGY.convertToAssets(shares);
    }
    
    
    function getProjectReports(uint256 epoch, uint256 projectId)
        external
        view
        returns (BugReport[] memory)
    {
        return epochProjectReports[epoch][projectId];
    }
    
    /**
     * @notice Get current available funds for distribution (including rollover)
     * @return Total available funds for bug bounty distribution
     */
    function getAvailableFunds() external view returns (uint256) {
        return totalAvailableFunds;
    }
    
    /**
     * @notice Get total cap pool (25% of available funds)
     * @return Total pool available for proportional distribution
     */
    function getTotalCapPool() external view returns (uint256) {
        return (totalAvailableFunds * TOTAL_CAP_PERCENTAGE) / 10000;
    }
    
    /**
     * @notice Get maximum payout per individual issue (5% of available funds)
     * @return Maximum payout amount per individual issue
     */
    function getMaxPayoutPerIssue() external view returns (uint256) {
        return (totalAvailableFunds * MAX_ISSUE_PERCENTAGE) / 10000;
    }
    
    /**
     * @notice Get proportional cap for a specific severity
     * @param severity The bug severity
     * @param globalWeight Total weight of all reports across all projects
     * @return Proportional cap for this severity from the 25% pool
     */
    function getProportionalCap(Severity severity, uint256 globalWeight) external view returns (uint256) {
        if (globalWeight == 0) return 0;
        uint256 totalCapPool = (totalAvailableFunds * TOTAL_CAP_PERCENTAGE) / 10000;
        return (totalCapPool * _getSeverityWeight(severity)) / globalWeight;
    }
}

