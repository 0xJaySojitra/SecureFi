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
    IERC4626Strategy public immutable yieldStrategy;
    
    /// @notice The underlying asset (e.g., USDC)
    IERC20Metadata public immutable asset;
    
    uint256 public constant EPOCH_DURATION = 30 days;
    uint256 public epochStartTime;
    uint256 public currentEpoch;
    
    // ============ STRUCTS ============
    
    struct Project {
        string name;
        string metadataURI;
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
        bool finalized;
    }
    
    // ============ MAPPINGS ============
    
    mapping(uint256 => Project) public projects; // projectId => Project
    mapping(uint256 => EpochData) public epochs;
    mapping(uint256 => mapping(uint256 => BugReport[])) public epochProjectReports; 
    // epoch => projectId => BugReport[]
    
    uint256 public projectCount;
    
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
    
    // ============ CONSTRUCTOR ============
    
    /**
     * @param _yieldStrategy Address of the YieldDonatingStrategy contract
     * @param _cantinaOperator Address of Cantina operator who can approve projects and submit reports
     * @param _admin Address of admin who can manage roles
     * @param _keeper Address of keeper who can trigger epoch advances and reports
     */
    constructor(
        address _yieldStrategy,
        address _cantinaOperator,
        address _admin,
        address _keeper
    ) {
        yieldStrategy = IERC4626Strategy(_yieldStrategy);
        asset = IERC20Metadata(yieldStrategy.asset());
        
        _grantRole(CANTINA_ROLE, _cantinaOperator);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _keeper);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        
        epochStartTime = block.timestamp;
        currentEpoch = 1;
    }
    
    // ============ PROJECT MANAGEMENT ============
    
    function registerProject(
        string memory name,
        string memory metadataURI
    ) external returns (uint256) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(metadataURI).length > 0, "Metadata URI required");
        require(projectCount < type(uint256).max, "Too many projects");
        projectCount++;
        projects[projectCount] = Project({
            name: name,
            metadataURI: metadataURI,
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
        require(
            block.timestamp >= epochStartTime + EPOCH_DURATION,
            "Epoch not finished"
        );
        // Step 1: Trigger strategy report to mint new donation shares
        // The keeper should have already called report() on the strategy before this,
        // but we document it here for clarity of the flow
        // Note: report() must be called externally by keeper BEFORE advanceEpoch()
        // Step 2: Redeem all accumulated strategy shares for underlying assets
        uint256 shares = yieldStrategy.balanceOf(address(this));
        uint256 yieldAmount = 0;
        if (shares > 0) {
            // Redeem shares to get underlying asset (USDC)
            // This triggers _freeFunds in the strategy, withdrawing from Aave vault
            yieldAmount = yieldStrategy.redeem(
                shares,
                address(this),  // receiver of assets
                address(this)   // owner of shares
            );
        }
        // Step 3: Record epoch data
        uint256 approvedCount = _countApprovedProjectsForEpoch(currentEpoch);

        epochs[currentEpoch] = EpochData({
            totalYield: yieldAmount,
            totalProjects: approvedCount,
            distributedAmount: 0,
            finalized: false
        });
        // Step 4: Advance epoch
        currentEpoch++;
        epochStartTime = block.timestamp;
        emit EpochAdvanced(currentEpoch, yieldAmount);
    }
    
    // ============ BUG REPORTING & PAYOUT ============
    
    /**
     * @notice Submits bug reports for multiple projects and distributes rewards
     * @dev Called by Cantina after reviewing bug reports for multiple projects in a completed epoch
     *      Optimized to distribute yield only among participating projects
     * @param epoch The epoch number for which bugs were reported
     * @param projectReports Array of ProjectReportSubmission containing projectId and their respective bug reports
     * @param signature Cantina's signature verifying the report batch
     */
    function submitBugReports(
        uint256 epoch,
        ProjectReportSubmission[] calldata projectReports,
        bytes calldata signature
    ) external onlyRole(CANTINA_ROLE) {
        require(epoch < currentEpoch, "Epoch not finalized");
        require(!epochs[epoch].finalized, "Epoch already distributed");
        require(epochs[epoch].totalYield > 0, "No yield for epoch");
        require(projectReports.length > 0, "No project reports provided");
        
        // Verify signature (Cantina signs the report batch)
        _verifyCantinaSignature(epoch, projectReports, signature);
        
        // Calculate yield allocation per project (divide among participating projects only)
        uint256 projectYield = epochs[epoch].totalYield / projectReports.length;
        
        // Process reports for each project
        for (uint256 p; p < projectReports.length;) {
            _processProjectReports(epoch, projectReports[p], projectYield);
            unchecked { ++p; }
        }
    }
    
    /**
     * @dev Internal function to process bug reports for a single project
     *      Separated to avoid stack too deep errors
     */
    function _processProjectReports(
        uint256 epoch,
        ProjectReportSubmission calldata projectReport,
        uint256 projectYield
    ) internal {
        uint256 projectId = projectReport.projectId;
        BugReportSubmission[] calldata reports = projectReport.reports;
        
    require(projects[projectId].approvedEpoch > 0 && projects[projectId].approvedEpoch <= epoch, "Project not approved for this epoch");
        require(reports.length > 0, "No reports for project");
        
        // Calculate severity weights for this project
        uint256 totalWeight = _calculateTotalWeight(reports);
        require(totalWeight > 0, "No valid reports");
        
        // Distribute to each reporter
        for (uint256 i; i < reports.length;) {
            uint256 payout = (projectYield * _getSeverityWeight(reports[i].severity)) / totalWeight;
            // Transfer underlying asset (USDC) to reporter
            IERC20(address(asset)).safeTransfer(reports[i].reporter, payout);
            // Record bug report
            epochProjectReports[epoch][projectId].push(BugReport({
                reportId: reports[i].reportId,
                reporter: reports[i].reporter,
                severity: reports[i].severity,
                paid: true,
                amount: payout
            }));
            // Track distributed amount
            epochs[epoch].distributedAmount += payout;
            emit BugPayoutExecuted(
                epoch,
                projectId,
                reports[i].reporter,
                payout,
                reports[i].severity
            );
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
        uint256 epoch,
        ProjectReportSubmission[] calldata projectReports,
        bytes calldata signature
    ) internal view {
        bytes32 messageHash = keccak256(abi.encode(
            epoch,
            projectReports
        ));
        
        bytes32 ethSignedHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));
        
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
        return yieldStrategy.balanceOf(address(this));
    }
    
    /**
     * @notice Get the asset value of accumulated shares
     * @dev Converts strategy shares to underlying asset amount
     * @return The asset value of shares held by this router
     */
    function getAccumulatedAssetValue() external view returns (uint256) {
        uint256 shares = yieldStrategy.balanceOf(address(this));
        if (shares == 0) return 0;
        return yieldStrategy.convertToAssets(shares);
    }
    
    /**
     * @notice Trigger a report on the strategy to harvest and mint donation shares
     * @dev Can only be called by keeper. This should be called before advanceEpoch()
     *      The report will:
     *      1. Call _harvestAndReport() to calculate total assets
     *      2. Calculate profit since last report
     *      3. Mint shares equal to profit amount to this router (dragonRouter)
     * @return profit The amount of profit detected
     * @return loss The amount of loss detected (if any)
     */
    function triggerStrategyReport() external onlyRole(KEEPER_ROLE) returns (uint256 profit, uint256 loss) {
        return yieldStrategy.report();
    }
    
    function getProjectReports(uint256 epoch, uint256 projectId)
        external
        view
        returns (BugReport[] memory)
    {
        return epochProjectReports[epoch][projectId];
    }
}

/**
 * @notice Helper struct for bug report submissions from Cantina
 * @dev Used as input parameter for submitBugReports function
 */
struct BugReportSubmission {
    bytes32 reportId;
    address reporter;
    SecurityRouter.Severity severity;
}

/**
 * @notice Helper struct for grouping multiple bug reports by project
 * @dev Used to submit bug reports for multiple projects in a single transaction
 */
struct ProjectReportSubmission {
    uint256 projectId;
    BugReportSubmission[] reports;
}
