// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title InterviewSoulboundToken
/// @notice A beginner-friendly SBT for interview completion records
contract InterviewSoulboundToken is ERC721 {
    uint256 private _nextTokenId = 1;

    // authorized interviewers
    mapping(address => bool) private _interviewers;

    struct InterviewData {
        uint256 participantId;
        uint256 interviewerId;
        string[] skills;
        uint256[] skillIds;
        string review;
        uint256 timestamp;
    }

    // tokenId -> InterviewData
    mapping(uint256 => InterviewData) private _tokenInterviewData;

    event SBTMinted(address indexed participant, uint256 indexed tokenId);

    modifier onlyInterviewer() {
        require(_interviewers[msg.sender], "Not an authorized interviewer");
        _;
    }

    constructor(address[] memory interviewers) ERC721("InterviewSoulboundToken", "iSBT") {
        for (uint256 i = 0; i < interviewers.length; i++) {
            _interviewers[interviewers[i]] = true;
        }
    }

    /// @notice Mint a soulbound token with interview details to participant
    /// @dev only authorized interviewer can call
    function mintSBT(
        address participant,
        uint256 participantId,
        uint256 interviewerId,
        string[] memory skills,
        uint256[] memory skillIds,
        string memory review
    ) external onlyInterviewer returns (uint256) {
        require(participant != address(0), "participant zero address");
        require(skills.length == skillIds.length, "skills/skillIds length mismatch");

        uint256 tokenId = _nextTokenId++;
        _safeMint(participant, tokenId);

        InterviewData storage data = _tokenInterviewData[tokenId];
        data.participantId = participantId;
        data.interviewerId = interviewerId;
        data.review = review;
        data.timestamp = block.timestamp;

        for (uint256 i = 0; i < skills.length; i++) {
            data.skills.push(skills[i]);
            data.skillIds.push(skillIds[i]);
        }

        emit SBTMinted(participant, tokenId);
        return tokenId;
    }

    /// @notice Get interview details for a token
    function getTokenDetails(uint256 tokenId)
        external
        view
        returns (
            uint256 participantId,
            uint256 interviewerId,
            string[] memory skills,
            uint256[] memory skillIds,
            string memory review,
            uint256 timestamp
        )
    {
        require(_tokenInterviewData[tokenId].timestamp != 0, "token does not exist");
        InterviewData storage data = _tokenInterviewData[tokenId];
        return (
            data.participantId,
            data.interviewerId,
            data.skills,
            data.skillIds,
            data.review,
            data.timestamp
        );
    }

    // Soulbound: disable transfers and approvals

    function transferFrom(address, address, uint256) public pure override {
        revert("Soulbound: transfer disabled");
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert("Soulbound: transfer disabled");
    }

    function approve(address, uint256) public pure override {
        revert("Soulbound: approval disabled");
    }

    function setApprovalForAll(address, bool) public pure override {
        revert("Soulbound: approval for all disabled");
    }

    function getApproved(uint256) public pure override returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) public pure override returns (bool) {
        return false;
    }
}