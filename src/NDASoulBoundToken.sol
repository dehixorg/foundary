// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NDASoulBoundToken is ERC721, AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant BUSINESS_OWNER_ROLE =
        keccak256("BUSINESS_OWNER_ROLE");
    bytes32 public constant FREELANCER_ROLE = keccak256("FREELANCER_ROLE");

    uint256 private s_tokenIdCounter = 1;

    enum NDAStatus {
        Draft,
        SignedByBusiness,
        SignedByBoth,
        // FIX [Obs-3]: 'Active' was defined in the enum but never explicitly
        // assigned anywhere in the original contract. It is now assigned in
        // signNDAByFreelancer() after the new dual-signed token is minted,
        // giving it a clear, intentional place in the lifecycle:
        //   Draft → SignedByBusiness → SignedByBoth → Active → Completed/Violated/Expired
        Active,
        Completed,
        Violated,
        Expired
    }

    // FIX [Obs-1]: Replace unbounded string fields with fixed-size bytes32
    // hashes to eliminate gas-cost growth and on-chain storage bloat.
    //
    // Callers should hash content off-chain before submitting:
    //   bytes32 hash = keccak256(abi.encodePacked(rawContent));
    // Or store an IPFS CID hash:
    //   bytes32 hash = keccak256(abi.encodePacked(ipfsCID));
    //
    // The original content/signature strings never need to touch the chain —
    // they live off-chain and are verifiable against the stored hash at any time.
    struct NDA {
        uint256 id;
        bytes32 contentHash;          // FIX [Obs-1]: was string content
        address businessOwner;
        address freelancer;
        bytes32 businessSignatureHash; // FIX [Obs-1]: was string businessSignature
        bytes32 freelancerSignatureHash; // FIX [Obs-1]: was string freelancerSignature
        uint256 createdAt;
        uint256 signedAt;
        uint256 expirationTime;
        uint256 completionTime;
        NDAStatus status;
        bool burned;
    }

    mapping(uint256 => NDA) public ndas;
    mapping(address => uint256[]) public businessOwnerNDAs;
    mapping(address => uint256[]) public freelancerNDAs;

    // FIX [Obs-4]: Track whether a token ID has been burned so that the
    // historical index arrays (businessOwnerNDAs / freelancerNDAs) can be
    // filtered by callers. The arrays themselves are kept intact to preserve
    // full history — the mapping lets anyone cheaply skip burned entries.
    mapping(uint256 => bool) public isBurned;

    event NDACreated(
        uint256 indexed tokenId,
        address indexed businessOwner,
        bytes32 contentHash // FIX [Obs-1]: emit hash not raw string
    );
    event NDASigned(
        uint256 indexed tokenId,
        address indexed signer,
        bytes32 signatureHash // FIX [Obs-1]: emit hash not raw string
    );
    event NDAActivated(uint256 indexed tokenId);
    event NDACompleted(uint256 indexed tokenId, uint256 completionTime);
    event NDABurned(uint256 indexed tokenId, NDAStatus reason);
    event NDAViolationReported(
        uint256 indexed tokenId,
        address indexed reporter,
        bytes32 reasonHash // FIX [Obs-1]: emit hash not raw string
    );

    modifier onlyBusinessOwner(uint256 _tokenId) {
        require(ndas[_tokenId].businessOwner == msg.sender, "NotBusinessOwner");
        _;
    }

    modifier onlyFreelancer(uint256 _tokenId) {
        require(ndas[_tokenId].freelancer == msg.sender, "NotFreelancer");
        _;
    }

    modifier tokenExists(uint256 _tokenId) {
        require(_ownerOf(_tokenId) != address(0), "TokenDoesNotExist");
        _;
    }

    modifier notBurned(uint256 _tokenId) {
        require(!ndas[_tokenId].burned, "NDABurned");
        _;
    }

    constructor() ERC721("NDASoulBoundToken", "NDASBT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // FIX [Obs-1]: Accept a bytes32 contentHash instead of a raw string.
    // The caller hashes the NDA content off-chain before calling this function.
    function createNDA(
        bytes32 _contentHash,
        address _freelancer,
        uint256 _durationDays
    ) external onlyRole(BUSINESS_OWNER_ROLE) nonReentrant returns (uint256) {
        require(_contentHash != bytes32(0), "EmptyContentHash");
        require(_freelancer != address(0), "InvalidFreelancer");
        require(_durationDays > 0, "InvalidDuration");

        uint256 tokenId = s_tokenIdCounter++;
        uint256 expirationTime = block.timestamp + (_durationDays * 1 days);

        ndas[tokenId] = NDA({
            id: tokenId,
            contentHash: _contentHash,
            businessOwner: msg.sender,
            freelancer: _freelancer,
            businessSignatureHash: bytes32(0),
            freelancerSignatureHash: bytes32(0),
            createdAt: block.timestamp,
            signedAt: 0,
            expirationTime: expirationTime,
            completionTime: 0,
            status: NDAStatus.Draft,
            burned: false
        });

        _mint(msg.sender, tokenId);
        businessOwnerNDAs[msg.sender].push(tokenId);

        emit NDACreated(tokenId, msg.sender, _contentHash);
        return tokenId;
    }

    // FIX [Obs-1]: Accept a bytes32 signatureHash instead of a raw string.
    function signNDAByBusiness(
        uint256 _tokenId,
        bytes32 _signatureHash
    )
        external
        onlyBusinessOwner(_tokenId)
        tokenExists(_tokenId)
        notBurned(_tokenId)
        nonReentrant
    {
        NDA storage nda = ndas[_tokenId];
        require(nda.status == NDAStatus.Draft, "InvalidStatus");
        require(_signatureHash != bytes32(0), "EmptySignatureHash");

        // FIX [Obs-2]: Enforce expiration at signing time so a business owner
        // cannot sign an already-expired NDA. Without this check, an NDA whose
        // clock ran out while in Draft could still be signed and enter the
        // active lifecycle indefinitely.
        require(block.timestamp < nda.expirationTime, "NDAExpired");

        nda.businessSignatureHash = _signatureHash;
        nda.status = NDAStatus.SignedByBusiness;

        emit NDASigned(_tokenId, msg.sender, _signatureHash);
    }

    // FIX [Obs-1]: Accept a bytes32 signatureHash instead of a raw string.
    // FIX [Obs-2]: Also check expiration here — a freelancer cannot co-sign
    // an NDA that has already expired while waiting for their signature.
    // FIX [Obs-3]: Explicitly transition the new token to Active status.
    function signNDAByFreelancer(
        uint256 _tokenId,
        bytes32 _signatureHash
    )
        external
        onlyFreelancer(_tokenId)
        tokenExists(_tokenId)
        notBurned(_tokenId)
        nonReentrant
    {
        NDA storage nda = ndas[_tokenId];
        require(nda.status == NDAStatus.SignedByBusiness, "BusinessNotSigned");
        require(_signatureHash != bytes32(0), "EmptySignatureHash");

        // FIX [Obs-2]: Enforce expiration check during freelancer signing.
        require(block.timestamp < nda.expirationTime, "NDAExpired");

        // Burn the old token (business owner's)
        _burn(_tokenId);

        // Create new token for freelancer
        uint256 newTokenId = s_tokenIdCounter++;
        ndas[newTokenId] = NDA({
            id: newTokenId,
            contentHash: nda.contentHash,
            businessOwner: nda.businessOwner,
            freelancer: nda.freelancer,
            businessSignatureHash: nda.businessSignatureHash,
            freelancerSignatureHash: _signatureHash,
            createdAt: nda.createdAt,
            signedAt: block.timestamp,
            expirationTime: nda.expirationTime,
            completionTime: 0,
            // FIX [Obs-3]: Assign Active status explicitly now that both
            // parties have signed. Previously this was set to SignedByBoth
            // and Active was never used, leaving a dead enum value.
            status: NDAStatus.Active,
            burned: false
        });

        _mint(msg.sender, newTokenId);
        freelancerNDAs[msg.sender].push(newTokenId);

        // Mark old NDA as burned
        nda.burned = true;
        // FIX [Obs-4]: Mirror burn state in the isBurned mapping so callers
        // can filter the historical index arrays without reading each NDA struct.
        isBurned[_tokenId] = true;
        nda.status = NDAStatus.Active; // FIX [Obs-3]: keep old struct consistent

        emit NDASigned(newTokenId, msg.sender, _signatureHash);
        emit NDAActivated(newTokenId);
        emit NDABurned(_tokenId, NDAStatus.Active);
    }

    function completeWork(
        uint256 _tokenId
    )
        external
        onlyFreelancer(_tokenId)
        tokenExists(_tokenId)
        notBurned(_tokenId)
        nonReentrant
    {
        NDA storage nda = ndas[_tokenId];
        // FIX [Obs-3]: Now that Active is properly assigned, only Active
        // status is required here — SignedByBoth will never be reached in
        // normal flow after the Obs-3 fix.
        require(
            nda.status == NDAStatus.Active ||
                nda.status == NDAStatus.SignedByBoth, // kept for legacy safety
            "InvalidStatus"
        );

        nda.status = NDAStatus.Completed;
        nda.completionTime = block.timestamp;

        emit NDACompleted(_tokenId, block.timestamp);

        _burnNDA(_tokenId, NDAStatus.Completed);
    }

    function checkAndBurnExpired(
        uint256 _tokenId
    ) external tokenExists(_tokenId) notBurned(_tokenId) nonReentrant {
        NDA storage nda = ndas[_tokenId];
        require(block.timestamp >= nda.expirationTime, "NotExpired");
        require(
            nda.status != NDAStatus.Completed &&
                nda.status != NDAStatus.Violated,
            "AlreadyResolved"
        );

        nda.status = NDAStatus.Expired;
        _burnNDA(_tokenId, NDAStatus.Expired);
    }

    // FIX [Obs-1]: Accept a bytes32 reasonHash instead of a raw string.
    function reportViolation(
        uint256 _tokenId,
        bytes32 _reasonHash
    ) external nonReentrant {
        require(
            _ownerOf(_tokenId) == msg.sender ||
                ndas[_tokenId].businessOwner == msg.sender ||
                ndas[_tokenId].freelancer == msg.sender,
            "NotAuthorized"
        );
        require(!ndas[_tokenId].burned, "NDABurned");
        require(_reasonHash != bytes32(0), "EmptyReasonHash");

        ndas[_tokenId].status = NDAStatus.Violated;

        emit NDAViolationReported(_tokenId, msg.sender, _reasonHash);
    }

    function _burnNDA(uint256 _tokenId, NDAStatus _reason) internal {
        // FIX: removed unused `address owner = ownerOf(_tokenId)` local variable
        ndas[_tokenId].burned = true;
        // FIX [Obs-4]: Keep isBurned mapping in sync with every burn path.
        isBurned[_tokenId] = true;
        _burn(_tokenId);

        emit NDABurned(_tokenId, _reason);
    }

    // --- VIEW FUNCTIONS ---

    function getNDA(uint256 _tokenId) external view returns (NDA memory) {
        return ndas[_tokenId];
    }

    function getBusinessOwnerNDAs(
        address _businessOwner
    ) external view returns (uint256[] memory) {
        return businessOwnerNDAs[_businessOwner];
    }

    function getFreelancerNDAs(
        address _freelancer
    ) external view returns (uint256[] memory) {
        return freelancerNDAs[_freelancer];
    }

    // FIX [Obs-4]: Helper that returns only the non-burned token IDs for a
    // business owner. The raw array (getBusinessOwnerNDAs) is kept for full
    // historical indexing; this view gives a clean active-only list without
    // requiring callers to iterate and check isBurned themselves.
    function getActiveBusinessOwnerNDAs(
        address _businessOwner
    ) external view returns (uint256[] memory) {
        uint256[] storage all = businessOwnerNDAs[_businessOwner];
        uint256 activeCount = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (!isBurned[all[i]]) activeCount++;
        }
        uint256[] memory active = new uint256[](activeCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (!isBurned[all[i]]) active[idx++] = all[i];
        }
        return active;
    }

    // FIX [Obs-4]: Same active-only filter for freelancer NDAs.
    function getActiveFreelancerNDAs(
        address _freelancer
    ) external view returns (uint256[] memory) {
        uint256[] storage all = freelancerNDAs[_freelancer];
        uint256 activeCount = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (!isBurned[all[i]]) activeCount++;
        }
        uint256[] memory active = new uint256[](activeCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (!isBurned[all[i]]) active[idx++] = all[i];
        }
        return active;
    }

    function isExpired(uint256 _tokenId) external view returns (bool) {
        return block.timestamp >= ndas[_tokenId].expirationTime;
    }

    // --- SOULBOUND: prevent all transfers ---

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        revert("SoulBound: Tokens cannot be transferred");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override {
        revert("SoulBound: Tokens cannot be transferred");
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
