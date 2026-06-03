# DEHIX Platform - Smart Contracts

A decentralized freelance marketplace built on Ethereum using Foundry, featuring soul-bound tokens, escrow management, and reputation systems.

## Overview

DEHIX is a blockchain-based platform connecting freelancers and businesses with secure contracts, verified credentials, and transparent payment handling. The platform uses Soul-Bound Tokens (SBTs) to create non-transferable, immutable records of work history, skills, and certifications.

---

## Smart Contracts

### 1. **Token (MyToken.sol)** - ERC20 Utility Token

**Purpose**: Governance and incentive token for the DEHIX platform

**Key Features**:
- ERC20 standard with minting and burning capabilities
- Role-based access control (MINTER_ROLE, BURNER_ROLE)
- Token name: DEHIX (Symbol: DXUT)

**User Workflow**:
1. Admin mints DEHIX tokens to reward stakers and freelancers
2. Users hold tokens for governance or liquidity
3. Tokens can be burned to remove them from circulation
4. Used as payment medium in the escrow system

**Key Functions**:
- `mint(address to, uint256 amount)` - Create new tokens
- `burn(address from, uint256 amount)` - Remove tokens from circulation

---

### 2. **FreelancerContract.sol** - Freelancer & Project Management

**Purpose**: Core platform contract managing freelancers, businesses, projects, and project-based escrow

**Key Features**:
- Register freelancers and businesses
- Create and manage projects
- Track freelancer applications
- Manage project-specific escrow accounts
- Oracle-based dispute resolution
- Multi-token support

**User Workflow**:

**For Businesses**:
1. Register business account with business ID
2. Create a project with unique project ID
3. Deposit funds into project escrow (supports multiple tokens)
4. Review freelancer applications
5. Select approved freelancer
6. Release payment after completion (via oracle consensus)

**For Freelancers**:
1. Register freelancer account with freelancer ID
2. Browse available projects
3. Apply to projects of interest
4. Get selected by business
5. Complete work and submit deliverables
6. Receive payment when oracles approve

**For Oracles** (Dispute Arbitrators):
1. Get assigned to specific escrow accounts
2. Vote on dispute resolution
3. Majority vote decides fund release/refund

**Key Functions**:
- `registerBusiness()` / `registerFreelancer()` - Account setup
- `createProject()` - Launch new project
- `applyToProject()` - Freelancer applies for work
- `createEscrow()` - Secure payment holding
- `vote()` - Oracle votes on disputes
- `releasePayment()` / `refundPayment()` - Finalize transactions

---

### 3. **EscrowContract.sol** - Secure Fund Management

**Purpose**: Standalone escrow system for holding and releasing funds safely

**Key Features**:
- Multi-token deposit and withdrawal
- Owner-controlled fund management
- Secure fund release mechanism
- Event logging for transparency

**User Workflow**:
1. Client creates escrow with freelancer address and token specification
2. Client deposits payment tokens into escrow
3. Work is completed
4. Owner (or authorized party) releases funds to freelancer
5. If dispute occurs, owner can refund client

**Key Functions**:
- `createEscrow()` - Initialize escrow account
- `depositFunds()` - Add payment to escrow
- `releaseFunds()` - Pay freelancer
- `refundClient()` - Return payment on dispute

---

### 4. **StakingRewards.sol** - Incentive System

**Purpose**: Reward loyal platform users for staking DEHIX tokens

**Key Features**:
- Configurable staking duration and reward rate
- Automatic reward calculation
- Non-custodial staking (users maintain control)

**User Workflow**:
1. User approves DEHIX tokens for staking
2. User deposits DEHIX tokens into staking contract
3. Rewards accumulate based on staked amount and duration
4. User can claim accrued rewards at any time
5. User withdraws principal stake whenever desired

**Key Functions**:
- `stake(uint256 amount)` - Deposit tokens
- `claimReward()` - Collect earned rewards
- `withdraw(uint256 amount)` - Remove staked tokens
- `setRewardsDuration()` - Admin sets reward periods

**Rewards Formula**: `rewardPerToken * (balanceOf[user] - userRewardPerTokenPaid[user])`

---

### 5. **FreelancerSoulBoundToken.sol** - Freelancer Profile & Reputation NFT

**Purpose**: Non-transferable NFT storing immutable freelancer profiles, skills, ratings, and achievement history

**Key Features**:
- One token per freelancer (soul-bound: non-transferable)
- Dynamic profile data (projects completed, ratings, earnings)
- Skill endorsement and verification system
- Achievement tracking (first project, verified freelancer, top earner, skill expert, etc.)
- Automated achievement unlocking based on milestones

**User Workflow**:

**Initial Setup**:
1. Admin mints SBT for new freelancer
2. Token stores freelancer ID, address, and initial profile

**During Work**:
1. After project completion, profile updates with:
   - `totalProjectsCompleted++`
   - `totalEarnings` increases
2. Business leaves rating (0-100%)
3. System calculates new `averageRating`

**Skill Management**:
1. Freelancer endorses new skill
2. Skill added to `endorsedSkills` array
3. Reputation role marks skill as `skillVerified`
4. `verifiedSkillCount` increments

**Achievement Unlock**:
1. System checks milestones automatically after each update:
   - FIRST_PROJECT: Complete 1 project
   - VERIFIED_FREELANCER: Get 5+ skills verified
   - HIGHLY_RATED: Average rating ≥ 90%
   - TOP_EARNER: Total earnings > threshold
   - SKILL_EXPERT: 10+ verified skills
2. Achievements are recorded in the NFT metadata

**Key Functions**:
- `mintSBT()` - Create profile token for freelancer
- `updateReputation()` - Update ratings and earnings
- `endorseSkill()` - Add skill with verification
- `revokeSkillEndorsement()` - Remove verified skill
- `_checkAndUnlockAchievements()` - Auto-detect milestones

---

### 6. **NDASoulBoundToken.sol** - Non-Disclosure Agreement NFT

**Purpose**: Cryptographic record of confidentiality agreements between businesses and freelancers

**Key Features**:
- Two-step signing process (business → freelancer)
- Content hashing (prevents on-chain bloat)
- 7 status states: Draft → SignedByBusiness → SignedByBoth → Active → Completed/Violated/Expired
- 72-hour dispute window for fraud claims
- Immutable record after completion

**User Workflow**:

**NDA Creation & Signing**:
1. Business Owner:
   - Creates NDA with IPFS content hash and signature
   - Status: `Draft` → `SignedByBusiness`

2. Freelancer:
   - Reviews NDA (content verified off-chain against hash)
   - Signs and submits signature hash
   - Status: `SignedByBoth` → `Active`

**During Engagement**:
- Work proceeds under NDA terms
- Status: `Active`

**NDA Completion**:
- On project end, status changes to `Completed`
- Content hash serves as cryptographic proof of agreement terms

**Dispute Handling** (Within 72 Hours):
- Either party can file dispute
- Status: `Violated` (for breach claims)
- Status: `Expired` (after 72 hours with no breach)

**Key Functions**:
- `createNDA()` - Business initiates agreement
- `signNDAByFreelancer()` - Freelancer agrees
- `markCompleted()` - Finalize agreement
- `markViolated()` - Report breach (within 72 hours)
- `isExpired()` - Check if dispute window closed

---

### 7. **InterviewSoulBoundToken.sol** - Interview Verification NFT

**Purpose**: Lightweight, beginner-friendly SBT recording interview completion and skill assessment

**Key Features**:
- Authorized interviewers mint tokens
- Records skills and skill IDs assessed
- Includes reviewer feedback and timestamp
- Simple ERC721 implementation

**User Workflow**:

**For Participants**:
1. Complete interview with authorized interviewer
2. Interviewer assesses 1+ skills
3. Interviewer mints SBT to participant address
4. NFT metadata includes:
   - Skills assessed (with IDs)
   - Interviewer ID and timestamp
   - Qualitative review/feedback

**For Interviewers**:
1. Get added to `_interviewers` mapping by admin
2. Review participant skills
3. Call `mintSBT()` to record interview
4. Token becomes permanent record (soul-bound)

**Use Cases**:
- Skill verification before hiring
- Pre-screening certification
- Track interview feedback history
- Build verifiable candidate profiles

**Key Functions**:
- `mintSBT()` - Record interview completion
- `addInterviewer()` - Admin registers new interviewer
- `getInterviewData()` - Retrieve interview details

---

### 8. **DEHIXFeePool.sol** - Fee Management System

**Purpose**: Centralized fee collection from external users using the DEHIX platform via relayers

**Key Features**:
- Dual-tier fee model:
  - **Scenario A** (Platform Users): Mint certificates for free
  - **Scenario B** (External Users): Pay per-mint fee
- User balance tracking
- Flexible fee withdrawal
- Admin treasury collection

**User Workflow**:

**External User Fee Payment**:
1. External user deposits MATIC into fee pool contract
2. User's balance tracked in `userBalance[address]`
3. When certificate is minted:
   - Relayer calls `deductFee(userAddress, paymentHash)`
   - Fee deducted from user's balance
   - `totalFeesCollected` incremented
4. User can withdraw unused balance anytime
5. Admin collects fees for DEHIX treasury

**Fee Parameters**:
- Default: 0.1 MATIC per certificate
- Admin can update via `setMintFee()`

**Key Functions**:
- `depositFee()` - User adds funds
- `withdrawFee()` - User retrieves unused balance
- `deductFee()` - Relayer charges user for mint
- `withdrawTreasuryFees()` - Admin collects platform fees
- `setMintFee()` - Admin adjusts fee rate

---

### 9. **DEHIXSBT.sol** - Work Certificate NFT (Primary SBT)

**Purpose**: Non-transferable, cryptographically signed certificates proving completed work and earning history

**Key Features**:
- EIP-712 signature verification (client approves via wallet)
- Relayer-based minting (backend submits tx, user pays gas indirectly)
- Soul-bound enforcement (all transfers blocked)
- 72-hour revocation window for fraud
- Payment hash tracking (prevents duplicate mints)
- Complete transfer/approval override (reverts all attempts)

**User Workflow**:

**Certificate Issuance**:
1. **Freelancer Completes Work**:
   - Work deliverables completed and accepted by client
   - Backend prepares certificate details (skills, earnings, project ID, etc.)

2. **Client Signs via Wallet**:
   - Client receives EIP-712 message in wallet
   - Message includes: freelancer address, amount, project ID, nonce, deadline
   - Client signs (no gas spent, purely cryptographic commitment)

3. **Relayer Submits On-Chain**:
   - Backend (relayer) calls `mintWithSignature()`
   - Passes signed message, signature, and payment hash
   - Contract verifies signature and mints token to freelancer

4. **Certificate Created**:
   - NFT minted to freelancer address (soul-bound)
   - Metadata stores: project details, earnings, timestamp
   - Payment hash recorded to prevent duplicate minting
   - Token becomes freelancer's earning record

**Certificate Dispute** (Within 72 Hours):
1. Admin detects fraudulent certificate
2. Admin calls `revokeCertificate()` before 72-hour window closes
3. Token marked as revoked
4. Fraudulent earnings removed from records

**Key Functions**:
- `mintWithSignature()` - Relayer mints certificate with client approval
- `revokeCertificate()` - Admin removes fraudulent tokens
- `isTokenRevoked()` - Check token validity
- `getFreelancerCertificates()` - View all certificates for freelancer
- *All transfer functions blocked* - `transfer()`, `approve()`, `safeTransferFrom()` revert

**Security Features**:
- EIP-712 ensures only authorized signers approve
- Soul-bound prevents secondary market abuse
- Payment hash prevents re-minting same work
- 72-hour admin revocation prevents long-term fraud
- Relayer pattern shields users from gas mechanics

---

## Workflow Summary: End-to-End Example

### Scenario: Software Developer Earns Certification

1. **Registration Phase**:
   - Developer registers on platform
   - Admin mints `FreelancerSoulBoundToken` with profile

2. **Project Phase**:
   - Business posts project in `FreelancerContract`
   - Developer applies
   - Business creates escrow with DEHIX tokens in `EscrowContract`
   - `NDASoulBoundToken` created and signed by both parties

3. **Work & Rewards Phase**:
   - Developer completes work
   - Passes interview → `InterviewSoulBoundToken` minted
   - Business signs certificate approval (EIP-712)
   - Relayer submits mint transaction
   - `DEHIXSBT` work certificate created

4. **Payment Phase**:
   - Oracles vote on work completion
   - Payment released from escrow
   - Developer stakes tokens in `StakingRewards` to earn more

5. **Reputation Updates**:
   - `FreelancerSoulBoundToken` profile updated:
     - Projects completed: +1
     - Total earnings: +amount
     - Average rating: updated based on review
   - Skills endorsed and verified
   - Achievements checked (FIRST_PROJECT unlocked if first)

6. **Dashboard View**:
   - Freelancer portfolio shows:
     - Profile NFT with reputation
     - Work certificates (DEHIXSBT tokens)
     - Verified skills
     - Achievements unlocked
     - Staking rewards earned

---

## Development Commands

### Build
```shell
forge build
```

### Test
```shell
forge test
```

### Format
```shell
forge fmt
```

### Gas Snapshots
```shell
forge snapshot
```

### Deploy
```shell
forge script script/DeployAll.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Local Node (Anvil)
```shell
anvil
```

### Cast (Interact with Contracts)
```shell
cast <subcommand>
```

---

## Documentation

Full Foundry documentation: https://book.getfoundry.sh/
