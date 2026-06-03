// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DEHIX Fee Pool
 * @author DEHIX Team
 * @notice Collects minting fees from external users who use the DEHIX extension
 * @dev Platform users (Scenario A) mint for free; external users (Scenario B) pay per mint.
 *
 * Fee Flow:
 *   1. External user deposits MATIC into this contract
 *   2. User's balance is tracked in a mapping
 *   3. When a certificate is minted, the SBT contract (or relayer) calls deductFee()
 *   4. Fee is deducted from the user's balance
 *   5. Unused balance can be withdrawn anytime
 *   6. Admin can withdraw collected fees to the DEHIX treasury
 */
contract DEHIXFeePool is Ownable {
    // ============ STATE VARIABLES ============

    /// @notice Per-user deposited balance (in wei)
    mapping(address => uint256) public userBalance;

    /// @notice Total fees collected since deployment
    uint256 public totalFeesCollected;

    /// @notice Cost per mint in wei (default: 0.1 MATIC = 100000000000000000 wei)
    uint256 public mintFeePerCertificate = 0.1 ether;

    /// @notice Address of the SBT contract authorized to deduct fees
    address public sbtContract;

    // ============ EVENTS ============

    event FeeDeposited(address indexed user, uint256 amount);
    event FeeWithdrawn(address indexed user, uint256 amount);
    event FeeDeducted(address indexed user, bytes32 paymentHash);
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);
    event SBTContractUpdated(address indexed oldSBT, address indexed newSBT);
    event TreasuryWithdrawal(address indexed to, uint256 amount);

    // ============ ERRORS ============

    error InvalidSBTContract();
    error OnlySBTContract();
    error ZeroDeposit();
    error InsufficientUserBalance(address user, uint256 required, uint256 available);
    error InsufficientContractBalance(uint256 requested, uint256 available);
    error WithdrawFailed();

    // ============ CONSTRUCTOR ============

    /**
     * @notice Deploy the fee pool
     * @param initialOwner Owner address (DEHIX team)
     * @param _sbtContract Address of the authorized SBT contract (can be address(0) initially, set later)
     */
    constructor(address initialOwner, address _sbtContract) Ownable(initialOwner) {
        sbtContract = _sbtContract;
    }

    // ============ USER FUNCTIONS ============

    /**
     * @notice Deposit MATIC to fund future certificate mints
     * @dev User can deposit once and mint many certificates.
     *      e.g., depositing 1 MATIC allows 10 mints at 0.1 MATIC each.
     */
    function depositFees() external payable {
        if (msg.value == 0) revert ZeroDeposit();
        userBalance[msg.sender] += msg.value;
        totalFeesCollected += msg.value;
        emit FeeDeposited(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw unused balance
     * @param amount Amount in wei to withdraw
     */
    function withdrawUnusedBalance(uint256 amount) external {
        if (userBalance[msg.sender] < amount) {
            revert InsufficientUserBalance(msg.sender, amount, userBalance[msg.sender]);
        }
        userBalance[msg.sender] -= amount;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert WithdrawFailed();

        emit FeeWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Check a user's deposited balance
     * @param user Address to query
     * @return balance The user's current balance in wei
     */
    function getUserBalance(address user) external view returns (uint256 balance) {
        return userBalance[user];
    }

    // ============ SBT CONTRACT INTEGRATION ============

    /**
     * @notice Deduct minting fee from a user's balance
     * @dev Only callable by the authorized SBT contract
     * @param user Address of the user to deduct from
     * @param paymentHash Payment transaction hash for event logging
     */
    function deductFee(address user, bytes32 paymentHash) external {
        if (msg.sender != sbtContract) revert OnlySBTContract();
        if (userBalance[user] < mintFeePerCertificate) {
            revert InsufficientUserBalance(user, mintFeePerCertificate, userBalance[user]);
        }
        userBalance[user] -= mintFeePerCertificate;
        emit FeeDeducted(user, paymentHash);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Withdraw collected fees to the DEHIX treasury
     * @param amount Amount in wei to withdraw
     */
    function withdrawTreasury(uint256 amount) external onlyOwner {
        if (address(this).balance < amount) {
            revert InsufficientContractBalance(amount, address(this).balance);
        }

        (bool success,) = payable(owner()).call{value: amount}("");
        if (!success) revert WithdrawFailed();

        emit TreasuryWithdrawal(owner(), amount);
    }

    /**
     * @notice Update the minting fee per certificate
     * @param newFee New fee in wei
     */
    function setMintFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = mintFeePerCertificate;
        mintFeePerCertificate = newFee;
        emit MintFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Update the authorized SBT contract address
     * @param _sbtContract New SBT contract address
     */
    function setSBTContract(address _sbtContract) external onlyOwner {
        if (_sbtContract == address(0)) revert InvalidSBTContract();
        address oldSBT = sbtContract;
        sbtContract = _sbtContract;
        emit SBTContractUpdated(oldSBT, _sbtContract);
    }

    // ============ RECEIVE MATIC ============

    /**
     * @notice Allow the contract to receive MATIC directly (auto-deposit)
     */
    receive() external payable {
        userBalance[msg.sender] += msg.value;
        emit FeeDeposited(msg.sender, msg.value);
    }
}
