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

    mapping(uint256 => string) public tokenIdToFreelancerId;
    mapping(address => uint256) public freelancerTokenId;

    struct FreelancerProfile {
        string freelancerId;
        address freelancerAddress;
        uint256 totalProjectsCompleted;
        uint256 averageRating; // stored as percentage (0-100)
        uint256 totalEarnings;
        uint256 tokensMinted;
        string[] endorsedSkills;
        bool[] skillVerified;
        // FIX [Obs-2]: Track the count of verified skills directly in the
        // profile struct so _checkAndUnlockAchievements() can read it in O(1)
        // instead of looping over the entire skillVerified array every time
        // updateReputation() is called. The counter is incremented in
        // endorseSkill() and decremented in revokeSkillEndorsement().
        uint256 verifiedSkillCount;
        uint256 createdAt;
        uint256 updatedAt;
    }

    mapping(uint256 => FreelancerProfile) public freelancerProfiles;

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
        string metadata;
    }

    mapping(uint256 => AchievementRecord[]) public tokenAchievements;

    // FIX [Obs-1]: Track which achievements have already been unlocked per
    // token so _unlockAchievementInternal() can reject duplicates.
    // Without this, every call to updateReputation() would re-trigger
    // HIGHLY_RATED, TOP_EARNER, etc. each time the thresholds were met,
    // producing duplicate records in tokenAchievements.
    mapping(uint256 => mapping(Achievement => bool)) private s_achievementUnlocked;

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

        freelancerProfiles[tokenId] = FreelancerProfile({
            freelancerId: _freelancerId,
            freelancerAddress: _freelancerAddress,
            totalProjectsCompleted: 0,
            averageRating: 0,
            totalEarnings: 0,
            tokensMinted: 1,
            endorsedSkills: new string[](0),
            skillVerified: new bool[](0),
            verifiedSkillCount: 0, // FIX [Obs-2]: initialise counter
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        emit TokenMinted(tokenId, _freelancerAddress, _freelancerId, block.timestamp);
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

        _checkAndUnlockAchievements(_tokenId);
    }

    // FIX [Obs-2]: Maintain verifiedSkillCount as skills are added so the
    // achievement check in _checkAndUnlockAchievements() never needs to loop.
    function endorseSkill(
        uint256 _tokenId,
        string calldata _skill,
        bool _verified
    ) external tokenExists(_tokenId) onlyRole(UPDATER_ROLE) nonReentrant {
        require(bytes(_skill).length > 0, "EmptySkill");

        FreelancerProfile storage profile = freelancerProfiles[_tokenId];
        profile.endorsedSkills.push(_skill);
        profile.skillVerified.push(_verified);

        // FIX [Obs-2]: Increment counter when a verified skill is added.
        if (_verified) {
            profile.verifiedSkillCount++;
        }

        profile.updatedAt = block.timestamp;
        emit SkillEndorsed(_tokenId, _skill, _verified, msg.sender, block.timestamp);
    }

    // FIX [Obs-2]: Keep verifiedSkillCount accurate when a skill is removed.
    function revokeSkillEndorsement(
        uint256 _tokenId,
        uint256 _skillIndex
    ) external tokenExists(_tokenId) onlyRole(UPDATER_ROLE) nonReentrant {
        FreelancerProfile storage profile = freelancerProfiles[_tokenId];
        require(_skillIndex < profile.endorsedSkills.length, "InvalidSkillIndex");

        string memory removedSkill = profile.endorsedSkills[_skillIndex];
        bool wasVerified = profile.skillVerified[_skillIndex]; // FIX [Obs-2]

        // Swap-and-pop to remove in O(1)
        uint256 lastIndex = profile.endorsedSkills.length - 1;
        profile.endorsedSkills[_skillIndex] = profile.endorsedSkills[lastIndex];
        profile.skillVerified[_skillIndex] = profile.skillVerified[lastIndex];
        profile.endorsedSkills.pop();
        profile.skillVerified.pop();

        // FIX [Obs-2]: Decrement counter if the removed skill was verified.
        if (wasVerified) {
            profile.verifiedSkillCount--;
        }

        profile.updatedAt = block.timestamp;
        emit ProfileDataUpdated(_tokenId, "SkillRevoked", removedSkill, block.timestamp);
    }

    // --- ACHIEVEMENT FUNCTIONS ---
    function unlockAchievement(
        uint256 _tokenId,
        Achievement _achievement,
        string calldata _metadata
    ) external tokenExists(_tokenId) onlyRole(REPUTATION_ROLE) nonReentrant {
        _unlockAchievementInternal(_tokenId, _achievement, _metadata);
    }

    // FIX [Obs-1]: Guard against duplicate achievement records. If an
    // achievement has already been unlocked for this token, the function
    // returns silently rather than pushing a second identical record.
    // This prevents tokenAchievements from accumulating duplicates every
    // time updateReputation() re-evaluates thresholds that were already met.
    function _unlockAchievementInternal(
        uint256 _tokenId,
        Achievement _achievement,
        string memory _metadata
    ) internal {
        // FIX [Obs-1]: Skip if this achievement was already unlocked.
        if (s_achievementUnlocked[_tokenId][_achievement]) {
            return;
        }

        // FIX [Obs-1]: Mark as unlocked before pushing the record.
        s_achievementUnlocked[_tokenId][_achievement] = true;

        tokenAchievements[_tokenId].push(AchievementRecord({
            achievement: _achievement,
            unlockedAt: block.timestamp,
            metadata: _metadata
        }));

        emit AchievementUnlocked(_tokenId, _achievement, _metadata, block.timestamp);
    }

    // FIX [Obs-2]: The SKILL_EXPERT check now reads verifiedSkillCount (O(1))
    // instead of looping over the entire skillVerified array (O(n)).
    // All other threshold checks are unchanged — they were already O(1).
    function _checkAndUnlockAchievements(uint256 _tokenId) internal {
        FreelancerProfile storage profile = freelancerProfiles[_tokenId];

        if (profile.totalProjectsCompleted == 1) {
            _unlockAchievementInternal(
                _tokenId,
                Achievement.FIRST_PROJECT,
                "Completed first project"
            );
        }

        if (profile.averageRating >= 90) {
            _unlockAchievementInternal(
                _tokenId,
                Achievement.HIGHLY_RATED,
                "Achieved 90+ rating"
            );
        }

        if (profile.totalEarnings >= 100000 * 10 ** 18) {
            _unlockAchievementInternal(
                _tokenId,
                Achievement.TOP_EARNER,
                "Earned 100,000+ tokens"
            );
        }

        // FIX [Obs-2]: O(1) read from the cached counter — no loop needed.
        if (profile.verifiedSkillCount >= 5) {
            _unlockAchievementInternal(
                _tokenId,
                Achievement.SKILL_EXPERT,
                "5+ verified skills"
            );
        }
    }

    // --- VIEW FUNCTIONS ---
    function getFreelancerProfile(
        uint256 _tokenId
    ) external view tokenExists(_tokenId) returns (FreelancerProfile memory) {
        return freelancerProfiles[_tokenId];
    }

    function getEndorsedSkills(
        uint256 _tokenId
    ) external view tokenExists(_tokenId) returns (string[] memory skills, bool[] memory verified) {
        FreelancerProfile storage profile = freelancerProfiles[_tokenId];
        return (profile.endorsedSkills, profile.skillVerified);
    }

    function getAchievements(
        uint256 _tokenId
    ) external view tokenExists(_tokenId) returns (AchievementRecord[] memory) {
        return tokenAchievements[_tokenId];
    }

    // FIX [Obs-1]: Expose the unlock state so front-ends can check whether
    // a specific achievement has already been earned without reading the full
    // achievements array.
    function hasAchievement(
        uint256 _tokenId,
        Achievement _achievement
    ) external view returns (bool) {
        return s_achievementUnlocked[_tokenId][_achievement];
    }

    function getTokenIdByFreelancer(
        address _freelancerAddress
    ) external view returns (uint256) {
        return freelancerTokenId[_freelancerAddress];
    }

    function getTotalTokensMinted() external view returns (uint256) {
        return s_tokenIdCounter - 1;
    }

    // --- SOULBOUND MECHANISM (PREVENT TRANSFERS) ---
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721) {
        revert("SoulBound: Tokens cannot be transferred");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721) {
        revert("SoulBound: Tokens cannot be transferred");
    }

    // --- SUPPORTSINTERFACE OVERRIDE ---
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
