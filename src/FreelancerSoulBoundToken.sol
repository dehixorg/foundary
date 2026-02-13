// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FreelancerSoulBoundToken is ERC721, AccessControl, ReentrancyGuard {
    // --- CONSTANTS & ROLES ---
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant REPUTATION_ROLE = keccak256("REPUTATION_ROLE");
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    // --- STATE VARIABLES ---
    uint256 private s_tokenIdCounter = 1;

    // Mapping from token ID to freelancer ID
    mapping(uint256 => string) public tokenIdToFreelancerId;

    // Mapping from freelancer address to token ID
    mapping(address => uint256) public freelancerTokenId;

    // Freelancer reputation and performance data
    struct FreelancerProfile {
        string freelancerId;
        address freelancerAddress;
        uint256 totalProjectsCompleted;
        uint256 averageRating; // Stored as percentage (0-100)
        uint256 totalEarnings;
        uint256 tokensMinted;
        string[] endorsedSkills;
        bool[] skillVerified;
        uint256 createdAt;
        uint256 updatedAt;
    }

    mapping(uint256 => FreelancerProfile) public freelancerProfiles;

    // Achievement tracking
    enum Achievement {
        FIRST_PROJECT,
        VERIFIED_FREELANCER,
        HIGHLY_RATED,
        TOP_EARNER,
        SKILL_EXPERT,
        COMMUNITY_CONTRIBUTOR
    }

    struct AchievementRecord {
        Achievement achievement;
        uint256 unlockedAt;
        string metadata; // Additional data for the achievement
    }

    mapping(uint256 => AchievementRecord[]) public tokenAchievements;

    // --- EVENTS ---
    event TokenMinted(
        uint256 indexed tokenId,
        address indexed freelancerAddress,
        string freelancerId,
        uint256 timestamp
    );

    event TokenBurned(
        uint256 indexed tokenId,
        address indexed freelancerAddress,
        uint256 timestamp
    );

    event ReputationUpdated(
        uint256 indexed tokenId,
        uint256 totalProjects,
        uint256 averageRating,
        uint256 totalEarnings,
        uint256 timestamp
    );

    event SkillEndorsed(
        uint256 indexed tokenId,
        string skill,
        bool verified,
        address indexed endorsedBy,
        uint256 timestamp
    );

    event AchievementUnlocked(
        uint256 indexed tokenId,
        Achievement achievement,
        string metadata,
        uint256 timestamp
    );

    event ProfileDataUpdated(
        uint256 indexed tokenId,
        string fieldName,
        string newValue,
        uint256 timestamp
    );

    // --- MODIFIERS ---
    modifier onlyTokenOwner(uint256 _tokenId) {
        require(ownerOf(_tokenId) == msg.sender, "NotTokenOwner");
        _;
    }

    modifier tokenExists(uint256 _tokenId) {
        require(_ownerOf(_tokenId) != address(0), "TokenDoesNotExist");
        _;
    }

    modifier soulBoundTransferCheck(address _from, address _to) {
        require(_from == address(0), "SoulBound: Token cannot be transferred");
        _;
    }

    // --- CONSTRUCTOR ---
    constructor() ERC721("FreelancerSoulBoundToken", "FSBLT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
        _grantRole(REPUTATION_ROLE, msg.sender);
    }

    // --- CORE FUNCTIONS ---

    function mintFreelancerToken(
        address _freelancerAddress,
        string calldata _freelancerId
    ) external onlyRole(MINTER_ROLE) nonReentrant returns (uint256) {
        require(_freelancerAddress != address(0), "ZeroAddress");
        require(bytes(_freelancerId).length > 0, "EmptyFreelancerId");
        require(
            freelancerTokenId[_freelancerAddress] == 0,
            "TokenAlreadyMinted"
        );

        uint256 tokenId = s_tokenIdCounter;
        s_tokenIdCounter++;
        _mint(_freelancerAddress, tokenId);

        tokenIdToFreelancerId[tokenId] = _freelancerId;
        freelancerTokenId[_freelancerAddress] = tokenId;

        // Initialize profile
        freelancerProfiles[tokenId] = FreelancerProfile({
            freelancerId: _freelancerId,
            freelancerAddress: _freelancerAddress,
            totalProjectsCompleted: 0,
            averageRating: 0,
            totalEarnings: 0,
            tokensMinted: 1,
            endorsedSkills: new string[](0),
            skillVerified: new bool[](0),
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        emit TokenMinted(
            tokenId,
            _freelancerAddress,
            _freelancerId,
            block.timestamp
        );
        return tokenId;
    }

    function burnToken(
        uint256 _tokenId
    ) external tokenExists(_tokenId) onlyRole(ADMIN_ROLE) nonReentrant {
        address freelancerAddress = ownerOf(_tokenId);
        delete tokenIdToFreelancerId[_tokenId];
        delete freelancerTokenId[freelancerAddress];
        delete freelancerProfiles[_tokenId];
        _burn(_tokenId);

        emit TokenBurned(_tokenId, freelancerAddress, block.timestamp);
    }

    // --- REPUTATION & PERFORMANCE FUNCTIONS ---

    function updateReputation(
        uint256 _tokenId,
        uint256 _projectsCompleted,
        uint256 _averageRating,
        uint256 _totalEarnings
    ) external tokenExists(_tokenId) onlyRole(REPUTATION_ROLE) nonReentrant {
        require(_averageRating <= 100, "InvalidRating");

        FreelancerProfile storage profile = freelancerProfiles[_tokenId];
        profile.totalProjectsCompleted = _projectsCompleted;
        profile.averageRating = _averageRating;
        profile.totalEarnings = _totalEarnings;
        profile.updatedAt = block.timestamp;

        emit ReputationUpdated(
            _tokenId,
            _projectsCompleted,
            _averageRating,
            _totalEarnings,
            block.timestamp
        );

        // Check and unlock achievements
        _checkAndUnlockAchievements(_tokenId);
    }

    function endorseSkill(
        uint256 _tokenId,
        string calldata _skill,
        bool _verified
    ) external tokenExists(_tokenId) onlyRole(UPDATER_ROLE) nonReentrant {
        require(bytes(_skill).length > 0, "EmptySkill");

        FreelancerProfile storage profile = freelancerProfiles[_tokenId];
        profile.endorsedSkills.push(_skill);
        profile.skillVerified.push(_verified);
        profile.updatedAt = block.timestamp;

        emit SkillEndorsed(
            _tokenId,
            _skill,
            _verified,
            msg.sender,
            block.timestamp
        );
    }

    function revokeSkillEndorsement(
        uint256 _tokenId,
        uint256 _skillIndex
    ) external tokenExists(_tokenId) onlyRole(UPDATER_ROLE) nonReentrant {
        FreelancerProfile storage profile = freelancerProfiles[_tokenId];
        require(
            _skillIndex < profile.endorsedSkills.length,
            "InvalidSkillIndex"
        );

        // Remove skill by replacing with last element and popping
        string memory removedSkill = profile.endorsedSkills[_skillIndex];
        profile.endorsedSkills[_skillIndex] = profile.endorsedSkills[
            profile.endorsedSkills.length - 1
        ];
        profile.skillVerified[_skillIndex] = profile.skillVerified[
            profile.skillVerified.length - 1
        ];

        profile.endorsedSkills.pop();
        profile.skillVerified.pop();
        profile.updatedAt = block.timestamp;

        emit ProfileDataUpdated(
            _tokenId,
            "SkillRevoked",
            removedSkill,
            block.timestamp
        );
    }

    // --- ACHIEVEMENT FUNCTIONS ---

    function unlockAchievement(
        uint256 _tokenId,
        Achievement _achievement,
        string calldata _metadata
    ) external tokenExists(_tokenId) onlyRole(REPUTATION_ROLE) nonReentrant {
        _unlockAchievementInternal(_tokenId, _achievement, _metadata);
    }

    function _unlockAchievementInternal(
        uint256 _tokenId,
        Achievement _achievement,
        string memory _metadata
    ) internal {
        AchievementRecord memory newAchievement = AchievementRecord({
            achievement: _achievement,
            unlockedAt: block.timestamp,
            metadata: _metadata
        });

        tokenAchievements[_tokenId].push(newAchievement);
        emit AchievementUnlocked(
            _tokenId,
            _achievement,
            _metadata,
            block.timestamp
        );
    }

    // @dev Checks and automatically unlocks achievements based on profile metrics

    function _checkAndUnlockAchievements(uint256 _tokenId) internal {
        FreelancerProfile storage profile = freelancerProfiles[_tokenId];

        // Check for FIRST_PROJECT
        if (profile.totalProjectsCompleted == 1) {
            _unlockAchievementInternal(
                _tokenId,
                Achievement.FIRST_PROJECT,
                "Completed first project"
            );
        }

        // Check for HIGHLY_RATED (average rating >= 90)
        if (profile.averageRating >= 90) {
            _unlockAchievementInternal(
                _tokenId,
                Achievement.HIGHLY_RATED,
                "Achieved 90+ rating"
            );
        }

        // Check for TOP_EARNER (based on earnings threshold)
        if (profile.totalEarnings >= 100000 * 10 ** 18) {
            // 100,000 tokens
            _unlockAchievementInternal(
                _tokenId,
                Achievement.TOP_EARNER,
                "Earned 100,000+ tokens"
            );
        }

        // Check for SKILL_EXPERT (5+ verified skills)
        uint256 verifiedSkillCount = 0;
        for (uint256 i = 0; i < profile.skillVerified.length; i++) {
            if (profile.skillVerified[i]) {
                verifiedSkillCount++;
            }
        }
        if (verifiedSkillCount >= 5) {
            _unlockAchievementInternal(
                _tokenId,
                Achievement.SKILL_EXPERT,
                "5+ verified skills"
            );
        }
    }

    // --- VIEW FUNCTIONS ---

    /// @notice Returns the FreelancerProfile for a given user address (if minted)
    function getProfile(
        address user
    ) external view returns (FreelancerProfile memory) {
        uint256 tokenId = freelancerTokenId[user];
        require(tokenId != 0, "NoSBTForUser");
        return freelancerProfiles[tokenId];
    }

    //@dev Returns the freelancer profile for a given token ID

    function getFreelancerProfile(
        uint256 _tokenId
    ) external view tokenExists(_tokenId) returns (FreelancerProfile memory) {
        return freelancerProfiles[_tokenId];
    }

    //@dev Returns all endorsed skills for a freelancer

    function getEndorsedSkills(
        uint256 _tokenId
    )
        external
        view
        tokenExists(_tokenId)
        returns (string[] memory skills, bool[] memory verified)
    {
        FreelancerProfile storage profile = freelancerProfiles[_tokenId];
        return (profile.endorsedSkills, profile.skillVerified);
    }

    // @dev Returns all achievements for a freelancer

    function getAchievements(
        uint256 _tokenId
    ) external view tokenExists(_tokenId) returns (AchievementRecord[] memory) {
        return tokenAchievements[_tokenId];
    }

    // @dev Returns the token ID for a given freelancer address
    function getTokenIdByFreelancer(
        address _freelancerAddress
    ) external view returns (uint256) {
        return freelancerTokenId[_freelancerAddress];
    }

    //@dev Returns the total number of tokens minted

    function getTotalTokensMinted() external view returns (uint256) {
        return s_tokenIdCounter - 1;
    }

    // --- SOULBOUND MECHANISM (PREVENT TRANSFERS) ---

    // @dev Override the transfer functions to prevent token transfers

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override(ERC721) {
        revert("SoulBound: Tokens cannot be transferred");
    }

    function safeTransferFrom(
        address,
        address,
        uint256,
        bytes memory
    ) public pure override(ERC721) {
        revert("SoulBound: Tokens cannot be transferred");
    }

    // --- SUPPORTSINTERFACE OVERRIDE ---
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
