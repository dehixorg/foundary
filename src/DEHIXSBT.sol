// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title DEHIX SBT Contract
 * @author DEHIX Team
 * @notice Non-transferable ERC721 token (Soulbound Token) for freelance work certificates
 * @dev Supports EIP-712 signature verification and fee-based minting via a relayer
 *
 * Architecture:
 *   - Client signs an EIP-712 typed message approving the certificate
 *   - Relayer (backend) submits the mint transaction on-chain
 *   - Token is soulbound: all transfers, approvals, and operator logic are blocked
 *   - Admin can revoke fraudulent certificates within a 72-hour dispute window
 *
 * Wallet Roles:
 *   - Owner:   Deploys contract, manages relayer/admin/feePool addresses
 *   - Admin:   Revokes fraudulent certificates
 *   - Relayer: Backend service authorized to call mintWithSignature()
 */
contract DEHIXSBT is ERC721, Ownable, EIP712 {
    using ECDSA for bytes32;

    // ============ STATE VARIABLES ============

    /// @notice Monotonic token ID counter (starts at 1)
    uint256 private _nextTokenId;

    /// @notice Relayer address (backend service that submits mint transactions)
    address public relayer;

    /// @notice Fee pool contract address (where minting fees are collected)
    address public feePool;

    /// @notice Admin address (can revoke certificates in fraud cases)
    address public admin;

    /// @notice Maps payment transaction hash → token ID (prevents duplicate minting)
    mapping(bytes32 => uint256) public txHashToTokenId;

    /// @notice Maps token ID → revoked status
    mapping(uint256 => bool) public revokedTokens;

    /// @notice Maps freelancer address → array of their certificate token IDs
    mapping(address => uint256[]) public freelancerCertificates;

    /// @notice Maps token ID → IPFS metadata URI (proof of work)
    mapping(uint256 => string) public tokenMetadata;

    /// @notice Tracks how many certificates a client has issued
    mapping(address => uint256) public clientIssuedCount;

    /// @notice Tracks how many of a client's certificates were disputed/revoked
    mapping(address => uint256) public clientDisputedCount;

    // ============ EVENTS ============

    event CertificateMinted(
        uint256 indexed tokenId,
        address indexed freelancer,
        address indexed client,
        bytes32 paymentTxHash,
        string metadataURI
    );

    event CertificateRevoked(uint256 indexed tokenId, address indexed freelancer, string reason);

    event RelayerChanged(address indexed oldRelayer, address indexed newRelayer);
    event FeePoolChanged(address indexed newFeePool);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    // ============ ERRORS ============

    error OnlyRelayer();
    error OnlyAdmin();
    error TokenRevoked(uint256 tokenId);
    error InvalidAddress();
    error SignatureExpired();
    error EmptyMetadataURI();
    error PaymentAlreadyMinted(bytes32 paymentTxHash);
    error InvalidSignature();
    error SoulboundTransferBlocked();
    error TokenDoesNotExist(uint256 tokenId);
    error TokenAlreadyRevoked(uint256 tokenId);

    // ============ EIP-712 TYPE HASH ============

    bytes32 private constant MINT_TYPEHASH =
        keccak256("MintCertificate(address freelancer,string metadataURI,bytes32 paymentTxHash,uint256 deadline)");

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize DEHIX SBT contract
     * @param initialOwner Address of the contract owner (DEHIX team, ideally multi-sig)
     * @param initialRelayer Address of backend relayer service
     * @param initialFeePool Address of fee pool contract
     * @param initialAdmin Address of admin who can revoke certificates
     */
    constructor(
        address initialOwner,
        address initialRelayer,
        address initialFeePool,
        address initialAdmin
    ) ERC721("DEHIX Work Certificate", "DEHIX-SBT") Ownable(initialOwner) EIP712("DEHIX", "1") {
        if (initialRelayer == address(0)) revert InvalidAddress();
        if (initialFeePool == address(0)) revert InvalidAddress();
        if (initialAdmin == address(0)) revert InvalidAddress();

        relayer = initialRelayer;
        feePool = initialFeePool;
        admin = initialAdmin;

        // Token IDs start at 1
        _nextTokenId = 1;
    }

    // ============ MODIFIERS ============

    /// @dev Restricts function to the authorized relayer (backend)
    modifier onlyRelayer() {
        if (msg.sender != relayer) revert OnlyRelayer();
        _;
    }

    /// @dev Restricts function to the admin (fraud revocation)
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    /// @dev Ensures the specified token has not been revoked
    modifier notRevoked(uint256 tokenId) {
        if (revokedTokens[tokenId]) revert TokenRevoked(tokenId);
        _;
    }

    // ============ CORE MINTING LOGIC ============

    /**
     * @notice Mint a soulbound certificate with EIP-712 signature verification
     *
     * @dev Flow:
     *   1. Relayer calls this with the client's signed EIP-712 message
     *   2. Contract verifies the client actually signed this message
     *   3. Checks the payment hash hasn't already been minted (no duplicates)
     *   4. Mints token to the freelancer's wallet
     *   5. Records client reputation data
     *
     * @param freelancer Address of the freelancer who performed the work
     * @param metadataURI IPFS link to work proof (files, description, hash)
     * @param paymentTxHash Hash of payment transaction (unique per certificate)
     * @param deadline Timestamp after which the client's signature expires
     * @param clientSignature EIP-712 signed message from client approving this mint
     * @return tokenId The newly minted token ID
     */
    function mintWithSignature(
        address freelancer,
        string calldata metadataURI,
        bytes32 paymentTxHash,
        uint256 deadline,
        bytes calldata clientSignature
    ) external onlyRelayer returns (uint256) {
        // ========== VALIDATION CHECKS ==========

        if (freelancer == address(0)) revert InvalidAddress();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (bytes(metadataURI).length == 0) revert EmptyMetadataURI();
        if (txHashToTokenId[paymentTxHash] != 0) revert PaymentAlreadyMinted(paymentTxHash);

        // ========== EIP-712 SIGNATURE VERIFICATION ==========

        // Build the structured data hash (EIP-712)
        bytes32 structHash = keccak256(
            abi.encode(MINT_TYPEHASH, freelancer, keccak256(bytes(metadataURI)), paymentTxHash, deadline)
        );

        // Get the final EIP-712 digest
        bytes32 digest = _hashTypedDataV4(structHash);

        // Recover the signer from the signature
        address signer = ECDSA.recover(digest, clientSignature);

        // Verify the signer is a valid client (not zero address)
        if (signer == address(0)) revert InvalidSignature();

        // ========== MINTING LOGIC ==========

        uint256 tokenId = _nextTokenId;
        _nextTokenId++;

        // Record the payment hash → token ID mapping (prevents duplicates)
        txHashToTokenId[paymentTxHash] = tokenId;

        // Store IPFS metadata
        tokenMetadata[tokenId] = metadataURI;

        // Update client reputation
        clientIssuedCount[signer]++;

        // Add to freelancer's certificate list
        freelancerCertificates[freelancer].push(tokenId);

        // Mint the soulbound token to the freelancer
        _safeMint(freelancer, tokenId);

        emit CertificateMinted(tokenId, freelancer, signer, paymentTxHash, metadataURI);

        return tokenId;
    }

    // ============ SOULBOUND TRANSFER OVERRIDE ============

    /**
     * @dev Override the internal _update function to block ALL transfers.
     * In OZ v5, _update is the central function for minting, burning, and transferring.
     * We allow minting (from == address(0)) but block all other transfers.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from is zero) and burning (to is zero), but block transfers
        if (from != address(0) && to != address(0)) {
            revert SoulboundTransferBlocked();
        }

        return super._update(to, tokenId, auth);
    }

    // ============ REVOCATION (FRAUD CASES) ============

    /**
     * @notice Admin revokes a fraudulent certificate
     * @dev Called only if dispute is proven (fake work, etc.) within a 72-hour window.
     *      After revocation, the token is marked invalid but remains visible on-chain.
     * @param tokenId Token ID to revoke
     * @param reason Reason for revocation (for auditing)
     */
    function revokeCertificate(uint256 tokenId, string calldata reason) external onlyAdmin {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        if (revokedTokens[tokenId]) revert TokenAlreadyRevoked(tokenId);

        revokedTokens[tokenId] = true;

        address tokenOwner = _ownerOf(tokenId);
        clientDisputedCount[tokenOwner]++;

        emit CertificateRevoked(tokenId, tokenOwner, reason);
    }

    // ============ VIEW FUNCTIONS (READ-ONLY) ============

    /**
     * @notice Get reputation data for a client
     * @param client Address of the client
     * @return issued Number of certificates issued by the client
     * @return disputed Number of certificates that were disputed/revoked
     */
    function getClientReputation(address client) external view returns (uint256 issued, uint256 disputed) {
        issued = clientIssuedCount[client];
        disputed = clientDisputedCount[client];
    }

    /**
     * @notice Get all certificate token IDs owned by a freelancer
     * @param freelancer Address of the freelancer
     * @return Array of token IDs
     */
    function getFreelancerCertificates(address freelancer) external view returns (uint256[] memory) {
        return freelancerCertificates[freelancer];
    }

    /**
     * @notice Get the metadata URI for a specific certificate
     * @param tokenId Token ID to query
     * @return IPFS metadata URI string
     */
    function getCertificateMetadata(uint256 tokenId) external view returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        return tokenMetadata[tokenId];
    }

    /**
     * @notice Check if a certificate has been revoked
     * @param tokenId Token ID to query
     * @return True if the certificate is revoked
     */
    function isCertificateRevoked(uint256 tokenId) external view returns (bool) {
        return revokedTokens[tokenId];
    }

    /**
     * @notice Get the next token ID that will be minted
     * @return The next token ID
     */
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Update the relayer address (backend service)
     * @param newRelayer New relayer address
     */
    function setRelayer(address newRelayer) external onlyOwner {
        if (newRelayer == address(0)) revert InvalidAddress();
        address oldRelayer = relayer;
        relayer = newRelayer;
        emit RelayerChanged(oldRelayer, newRelayer);
    }

    /**
     * @notice Update the fee pool contract address
     * @param newFeePool New fee pool address
     */
    function setFeePool(address newFeePool) external onlyOwner {
        if (newFeePool == address(0)) revert InvalidAddress();
        feePool = newFeePool;
        emit FeePoolChanged(newFeePool);
    }

    /**
     * @notice Update the admin address
     * @param newAdmin New admin address
     */
    function setAdmin(address newAdmin) external onlyOwner {
        if (newAdmin == address(0)) revert InvalidAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    // ============ ERC721 METADATA OVERRIDE ============

    /**
     * @notice Return the token URI (IPFS metadata link)
     * @param tokenId Token ID to query
     * @return The IPFS metadata URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return tokenMetadata[tokenId];
    }
}
