# SecurityRouter - Bug Bounty Distribution System

## Overview

The SecurityRouter acts as the "dragonRouter" in the YieldDonating Strategy ecosystem, receiving donated yield and distributing it as bug bounty rewards to security researchers through Cantina integration.

## Key Features

### 🎯 **25% Total Cap + 5% Per-Issue Limit**
- Uses 25% of available funds for monthly distribution
- No single bug can receive more than 5% of total available funds
- Remaining funds rollover to next epoch for larger reward pools

### 🔄 **Epoch-Based Distribution**
- Monthly cycles (30 days) for yield collection and distribution
- Automatic rollover of unused funds to next epoch
- Cross-epoch reporting support (projects can receive reports anytime)

### 🏆 **Severity-Based Rewards**
Rewards are calculated based on bug severity with weighted distribution:
- **Critical**: 5 points
- **High**: 3 points
- **Medium**: 2 points
- **Low**: 1 point
- **Informational**: 1 point

## Core Functions

### Project Management

#### `registerProject(string name, string metadata)`
- Allows projects to register for bug bounty funding
- Projects must be approved by Cantina before receiving rewards
- Returns unique project ID for tracking

#### `approveProject(uint256 projectId)` 
- **Cantina only**: Approves registered projects for bug bounty funding
- Only approved projects can receive bug report submissions
- Projects approved in any epoch can receive reports in future epochs

### Epoch Management

#### `advanceEpoch()`
- **Keeper only**: Advances to next epoch and collects yield
- Redeems strategy shares for underlying USDC
- Calculates rollover amount from previous epoch
- Updates total available funds for distribution

### Bug Report Submission

#### `submitBugReports(ProjectReportSubmission[] projectReports, bytes signature)`
- **Cantina only**: Submits verified bug reports for reward distribution
- Requires cryptographic signature for verification
- Distributes rewards immediately based on severity and caps
- Can submit reports for any approved project regardless of epoch

## Reward Distribution Formula

### Step-by-Step Calculation

1. **Calculate Global Weight**
   ```solidity
   globalTotalWeight = sum of all severity weights across all projects
   ```

2. **Calculate Total Cap Pool (25%)**
   ```solidity
   totalCapPool = (totalAvailableFunds * 2500) / 10000
   ```

3. **Calculate Per-Issue Cap (5%)**
   ```solidity
   maxPerIssue = (totalAvailableFunds * 500) / 10000
   ```

4. **For Each Bug Report**
   ```solidity
   // Severity-based calculation
   severityBasedPayout = (projectYield * severityWeight) / projectTotalWeight
   
   // Proportional cap from 25% pool
   proportionalCap = (totalCapPool * severityWeight) / globalTotalWeight
   
   // Final payout (minimum of all three)
   finalPayout = min(severityBasedPayout, proportionalCap, maxPerIssue)
   ```

### Example Calculations

**Scenario: 362,437 USDC available, 5 total bugs**
- Total cap pool (25%): 90,609 USDC
- Max per issue (5%): 18,121 USDC
- Global weight: 11 points (1 Critical + 2 Medium + 2 Low/Info)

**Results:**
- Critical bug: 18,121 USDC (hits 5% cap)
- Medium bugs: 16,474 USDC each (proportional)
- Low/Info bugs: 8,237 USDC each (proportional)
- Total distributed: 67,543 USDC (18.6%)
- Remaining for rollover: 294,894 USDC

## Access Control

### Roles

#### `DEFAULT_ADMIN_ROLE`
- Can grant/revoke other roles
- Emergency governance functions

#### `KEEPER_ROLE` 
- Can advance epochs (`advanceEpoch()`)
- Triggers yield collection and fund updates

#### `CANTINA_ROLE`
- Can approve projects (`approveProject()`)
- Can submit bug reports (`submitBugReports()`)
- Maintains signature verification keys

### Role Management
```solidity
// Grant roles during deployment
grantRole(KEEPER_ROLE, keeperAddress);
grantRole(CANTINA_ROLE, cantinaOperator);

// Revoke roles if needed
revokeRole(CANTINA_ROLE, oldCantinaOperator);
```

## Events

### Project Events
```solidity
event ProjectRegistered(uint256 indexed projectId, string name, address indexed registrant);
event ProjectApproved(uint256 indexed projectId, address indexed approver);
```

### Epoch Events
```solidity
event EpochAdvanced(uint256 indexed newEpoch, uint256 yieldCollected, uint256 rolloverAmount);
```

### Reward Events
```solidity
event BugReportSubmitted(
    uint256 indexed projectId,
    bytes32 indexed reportId,
    address indexed reporter,
    Severity severity,
    uint256 reward
);
```

## Security Features

### Signature Verification
- All bug reports must include valid Cantina signature
- Prevents unauthorized reward distribution
- Uses Ethereum signed message format

### Cap Protection
- 5% per-issue cap prevents single bug from draining funds
- 25% total cap ensures sustainable distribution
- Rollover mechanism preserves unused funds

### Access Control
- Role-based permissions for critical functions
- Multi-signature support for admin functions
- Emergency pause capabilities

## Integration Guide

### For Projects
1. Call `registerProject()` with project details
2. Wait for Cantina approval via `approveProject()`
3. Receive bug bounty funding when researchers find issues

### For Cantina
1. Review registered projects and approve worthy ones
2. Verify bug reports from security researchers
3. Submit signed reports via `submitBugReports()`
4. Maintain secure signature keys

### For Security Researchers
1. Find bugs in approved projects
2. Report to Cantina for verification
3. Receive USDC rewards automatically upon Cantina submission
4. Rewards based on severity and available funds

## Error Handling

### Common Errors
- `"Project not found"`: Invalid project ID
- `"Project not approved"`: Trying to submit reports for unapproved project
- `"Invalid signature"`: Cantina signature verification failed
- `"No funds available"`: Attempting distribution with zero funds
- `"!keeper"` / `"!cantina"`: Access control violations

### Recovery Mechanisms
- Emergency admin can pause contract
- Funds can be recovered in emergency situations
- Role management allows operator changes

## Gas Optimization

### Batch Operations
- Submit multiple project reports in single transaction
- Efficient signature verification for multiple reports
- Optimized storage access patterns

### Storage Efficiency
- Packed structs for gas savings
- Minimal storage writes during distribution
- Efficient mapping structures for lookups

## Upgrade Path

The SecurityRouter is designed to be:
- **Immutable**: Core logic cannot be changed
- **Configurable**: Parameters can be adjusted via governance
- **Extensible**: New features can be added via proxy patterns

For major upgrades, a new SecurityRouter would need to be deployed and integrated with the YieldDonatingStrategy.
