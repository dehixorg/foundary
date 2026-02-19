# NDA Soulbound Token

A Soulbound Token (SBT) implementation for managing Non-Disclosure Agreements (NDAs) between business owners and freelancers in a decentralized manner.

## Overview

This contract implements a comprehensive NDA management system using Soulbound Tokens that cannot be transferred once minted. The system handles the entire lifecycle of NDAs from creation to automatic burning based on predefined conditions.

## Key Features

### 1. NDA Creation and Signing
- **Business Owner**: Creates NDA with content and sets expiration duration
- **Freelancer**: Signs the NDA, creating a new SBT while burning the original

### 2. Automatic Burning Mechanisms
- **Work Completion**: NDA burns automatically when freelancer marks work as complete
- **Time Expiration**: NDA burns automatically after the set duration expires
- **Violation Reporting**: Admin gets notified of violations for human intervention

### 3. Soulbound Nature
- Tokens cannot be transferred between addresses
- Each NDA is permanently tied to its owner

## Contract Architecture

### Roles
- `ADMIN_ROLE`: Contract administration
- `BUSINESS_OWNER_ROLE`: Can create NDAs
- `FREELANCER_ROLE`: Can sign and complete NDAs

### NDA States
```solidity
enum NDAStatus {
    Draft,           // Initial state after creation
    SignedByBusiness, // Business owner has signed
    SignedByBoth,    // Both parties have signed
    Active,          // NDA is active
    Completed,       // Work completed, NDA burned
    Violated,        // Violation reported
    Expired          // Time expired, NDA burned
}
```

### Key Functions

#### For Business Owners
- `createNDA(string content, address freelancer, uint256 durationDays)`: Create a new NDA
- `signNDAByBusiness(uint256 tokenId, string signature)`: Sign the NDA

#### For Freelancers
- `signNDAByFreelancer(uint256 tokenId, string signature)`: Sign NDA and mint new SBT
- `completeWork(uint256 tokenId)`: Mark work as complete and burn NDA

#### Administrative
- `reportViolation(uint256 tokenId, string reason)`: Report NDA violation
- `checkAndBurnExpired(uint256 tokenId)`: Check and burn expired NDAs

## Workflow

1. **Business Owner** creates NDA with content and duration
2. **Business Owner** signs the NDA
3. **Freelancer** signs the NDA, burning the old SBT and minting a new one
4. NDA becomes active
5. **Freelancer** completes work, automatically burning the NDA
6. If time expires before completion, anyone can call `checkAndBurnExpired` to burn it
7. If violation occurs, any party can report it, notifying admin for intervention

## Events

- `NDACreated`: Emitted when NDA is created
- `NDASigned`: Emitted when NDA is signed by a party
- `NDAActivated`: Emitted when both parties have signed
- `NDACompleted`: Emitted when work is completed
- `NDABurned`: Emitted when NDA is burned
- `NDAViolationReported`: Emitted when violation is reported

## Security Considerations

- All tokens are soulbound and cannot be transferred
- Access control ensures only authorized parties can perform actions
- Reentrancy protection on state-changing functions
- Input validation for all parameters

## Usage Example

```solidity
// Deploy contract
NDASoulBoundToken ndaToken = new NDASoulBoundToken();

// Grant roles
ndaToken.grantRole(ndaToken.BUSINESS_OWNER_ROLE(), businessOwner);
ndaToken.grantRole(ndaToken.FREELANCER_ROLE(), freelancer);

// Business owner creates NDA
uint256 tokenId = ndaToken.createNDA("NDA content here", freelancer, 30);

// Business owner signs
ndaToken.signNDAByBusiness(tokenId, "Business signature");

// Freelancer signs (burns old, mints new)
ndaToken.signNDAByFreelancer(tokenId, "Freelancer signature");

// Freelancer completes work (burns NDA)
ndaToken.completeWork(newTokenId);
```

## Testing

Run the test suite:
```bash
forge test --match-path test/NDASoulBoundToken.t.sol
```

## Deployment

Ensure OpenZeppelin contracts are available via remappings, then deploy:
```bash
forge create NDASoulBoundToken
```