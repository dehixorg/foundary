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
        Active,
        Completed,
        Violated,
        Expired
    }

    struct NDA {
        uint256 id;
        string content;
        address businessOwner;
        address freelancer;
        string businessSignature;
        string freelancerSignature;
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

    event NDACreated(
        uint256 indexed tokenId,
        address indexed businessOwner,
        string content
    );
    event NDASigned(
        uint256 indexed tokenId,
        address indexed signer,
        string signature
    );
    event NDAActivated(uint256 indexed tokenId);
    event NDACompleted(uint256 indexed tokenId, uint256 completionTime);
    event NDABurned(uint256 indexed tokenId, NDAStatus reason);
    event NDAViolationReported(
        uint256 indexed tokenId,
        address indexed reporter,
        string reason
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

    function createNDA(
        string calldata _content,
        address _freelancer,
        uint256 _durationDays
    ) external onlyRole(BUSINESS_OWNER_ROLE) nonReentrant returns (uint256) {
        require(bytes(_content).length > 0, "EmptyContent");
        require(_freelancer != address(0), "InvalidFreelancer");
        require(_durationDays > 0, "InvalidDuration");

        uint256 tokenId = s_tokenIdCounter++;
        uint256 expirationTime = block.timestamp + (_durationDays * 1 days);

        ndas[tokenId] = NDA({
            id: tokenId,
            content: _content,
            businessOwner: msg.sender,
            freelancer: _freelancer,
            businessSignature: "",
            freelancerSignature: "",
            createdAt: block.timestamp,
            signedAt: 0,
            expirationTime: expirationTime,
            completionTime: 0,
            status: NDAStatus.Draft,
            burned: false
        });

        _mint(msg.sender, tokenId);
        businessOwnerNDAs[msg.sender].push(tokenId);

        emit NDACreated(tokenId, msg.sender, _content);
        return tokenId;
    }

    function signNDAByBusiness(
        uint256 _tokenId,
        string calldata _signature
    )
        external
        onlyBusinessOwner(_tokenId)
        tokenExists(_tokenId)
        notBurned(_tokenId)
        nonReentrant
    {
        NDA storage nda = ndas[_tokenId];
        require(nda.status == NDAStatus.Draft, "InvalidStatus");
        require(bytes(_signature).length > 0, "EmptySignature");

        nda.businessSignature = _signature;
        nda.status = NDAStatus.SignedByBusiness;

        emit NDASigned(_tokenId, msg.sender, _signature);
    }

    function signNDAByFreelancer(
        uint256 _tokenId,
        string calldata _signature
    )
        external
        onlyFreelancer(_tokenId)
        tokenExists(_tokenId)
        notBurned(_tokenId)
        nonReentrant
    {
        NDA storage nda = ndas[_tokenId];
        require(nda.status == NDAStatus.SignedByBusiness, "BusinessNotSigned");
        require(bytes(_signature).length > 0, "EmptySignature");

        // Burn the old token (business owner's)
        _burn(_tokenId);

        // Create new token for freelancer
        uint256 newTokenId = s_tokenIdCounter++;
        ndas[newTokenId] = NDA({
            id: newTokenId,
            content: nda.content,
            businessOwner: nda.businessOwner,
            freelancer: nda.freelancer,
            businessSignature: nda.businessSignature,
            freelancerSignature: _signature,
            createdAt: nda.createdAt,
            signedAt: block.timestamp,
            expirationTime: nda.expirationTime,
            completionTime: 0,
            status: NDAStatus.SignedByBoth,
            burned: false
        });

        _mint(msg.sender, newTokenId);
        freelancerNDAs[msg.sender].push(newTokenId);

        // Mark old NDA as burned
        nda.burned = true;
        nda.status = NDAStatus.SignedByBoth;

        emit NDASigned(newTokenId, msg.sender, _signature);
        emit NDAActivated(newTokenId);
        emit NDABurned(_tokenId, NDAStatus.SignedByBoth);
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
        require(
            nda.status == NDAStatus.Active ||
                nda.status == NDAStatus.SignedByBoth,
            "InvalidStatus"
        );

        nda.status = NDAStatus.Completed;
        nda.completionTime = block.timestamp;

        emit NDACompleted(_tokenId, block.timestamp);

        // Burn the NDA after completion
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

    function reportViolation(
        uint256 _tokenId,
        string calldata _reason
    ) external nonReentrant {
        require(
            _ownerOf(_tokenId) == msg.sender ||
                ndas[_tokenId].businessOwner == msg.sender ||
                ndas[_tokenId].freelancer == msg.sender,
            "NotAuthorized"
        );
        require(!ndas[_tokenId].burned, "NDABurned");

        ndas[_tokenId].status = NDAStatus.Violated;

        emit NDAViolationReported(_tokenId, msg.sender, _reason);
        // Note: Admin will monitor this event off-chain and take action
    }

    function _burnNDA(uint256 _tokenId, NDAStatus _reason) internal {
        address owner = ownerOf(_tokenId);
        ndas[_tokenId].burned = true;
        _burn(_tokenId);

        emit NDABurned(_tokenId, _reason);
    }

    // View functions
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

    function isExpired(uint256 _tokenId) external view returns (bool) {
        return block.timestamp >= ndas[_tokenId].expirationTime;
    }

    // Soulbound mechanism - prevent transfers
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
