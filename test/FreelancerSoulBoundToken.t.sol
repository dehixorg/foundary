// test/FreelancerSoulBoundToken.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FreelancerSoulBoundToken} from "../src/FreelancerSoulBoundToken.sol";

contract FreelancerSoulBoundTokenTest is Test {
    FreelancerSoulBoundToken public token;

    address public admin;
    address public minter;
    address public updater;
    address public reputationManager;
    address public freelancer1;
    address public freelancer2;

    function setUp() public {
        token = new FreelancerSoulBoundToken();

        admin = makeAddr("admin");
        minter = makeAddr("minter");
        updater = makeAddr("updater");
        reputationManager = makeAddr("reputationManager");
        freelancer1 = makeAddr("freelancer1");
        freelancer2 = makeAddr("freelancer2");

        // Grant roles
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.UPDATER_ROLE(), updater);
        token.grantRole(token.REPUTATION_ROLE(), reputationManager);
        token.grantRole(token.ADMIN_ROLE(), admin);
    }

    function test_Constructor() public {
        assertEq(token.name(), "FreelancerSoulBoundToken");
        assertEq(token.symbol(), "FSBLT");
        assertTrue(token.hasRole(token.ADMIN_ROLE(), address(this)));
        assertTrue(token.hasRole(token.MINTER_ROLE(), address(this)));
        assertTrue(token.hasRole(token.UPDATER_ROLE(), address(this)));
        assertTrue(token.hasRole(token.REPUTATION_ROLE(), address(this)));
    }

    function test_MintFreelancerToken() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        assertEq(tokenId, 1);
        assertEq(token.ownerOf(tokenId), freelancer1);
        assertEq(token.tokenIdToFreelancerId(tokenId), "freelancer_1");
        assertEq(token.freelancerTokenId(freelancer1), tokenId);

        FreelancerSoulBoundToken.FreelancerProfile memory profile = token
            .getFreelancerProfile(tokenId);
        assertEq(profile.freelancerId, "freelancer_1");
        assertEq(profile.freelancerAddress, freelancer1);
        assertEq(profile.totalProjectsCompleted, 0);
        assertEq(profile.averageRating, 0);
        assertEq(profile.totalEarnings, 0);
        assertEq(profile.tokensMinted, 1);
        assertEq(profile.endorsedSkills.length, 0);
        assertEq(profile.skillVerified.length, 0);
    }

    function test_MintFreelancerToken_RevertIfZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert("ZeroAddress");
        token.mintFreelancerToken(address(0), "freelancer_1");
    }

    function test_MintFreelancerToken_RevertIfEmptyId() public {
        vm.prank(minter);
        vm.expectRevert("EmptyFreelancerId");
        token.mintFreelancerToken(freelancer1, "");
    }

    function test_MintFreelancerToken_RevertIfAlreadyMinted() public {
        vm.prank(minter);
        token.mintFreelancerToken(freelancer1, "freelancer_1");

        vm.prank(minter);
        vm.expectRevert("TokenAlreadyMinted");
        token.mintFreelancerToken(freelancer1, "freelancer_1_again");
    }

    function test_BurnToken() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(admin);
        token.burnToken(tokenId);

        vm.expectRevert();
        token.ownerOf(tokenId);
    }

    function test_BurnToken_RevertIfNotAdmin() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(freelancer1);
        vm.expectRevert();
        token.burnToken(tokenId);
    }

    function test_UpdateReputation() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(reputationManager);
        token.updateReputation(tokenId, 5, 95, 1000e18);

        FreelancerSoulBoundToken.FreelancerProfile memory profile = token
            .getFreelancerProfile(tokenId);
        assertEq(profile.totalProjectsCompleted, 5);
        assertEq(profile.averageRating, 95);
        assertEq(profile.totalEarnings, 1000e18);
    }

    function test_UpdateReputation_RevertIfInvalidRating() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(reputationManager);
        vm.expectRevert("InvalidRating");
        token.updateReputation(tokenId, 5, 101, 1000e18);
    }

    function test_EndorseSkill() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(updater);
        token.endorseSkill(tokenId, "Solidity", true);

        (string[] memory skills, bool[] memory verified) = token
            .getEndorsedSkills(tokenId);
        assertEq(skills.length, 1);
        assertEq(skills[0], "Solidity");
        assertTrue(verified[0]);
    }

    function test_EndorseSkill_RevertIfEmptySkill() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(updater);
        vm.expectRevert("EmptySkill");
        token.endorseSkill(tokenId, "", true);
    }

    function test_RevokeSkillEndorsement() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(updater);
        token.endorseSkill(tokenId, "Solidity", true);

        vm.prank(updater);
        token.revokeSkillEndorsement(tokenId, 0);

        (string[] memory skills, bool[] memory verified) = token
            .getEndorsedSkills(tokenId);
        assertEq(skills.length, 0);
        assertEq(verified.length, 0);
    }

    function test_RevokeSkillEndorsement_RevertIfInvalidIndex() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(updater);
        vm.expectRevert("InvalidSkillIndex");
        token.revokeSkillEndorsement(tokenId, 0);
    }

    function test_UnlockAchievement() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(reputationManager);
        token.unlockAchievement(
            tokenId,
            FreelancerSoulBoundToken.Achievement.FIRST_PROJECT,
            "First project completed"
        );

        FreelancerSoulBoundToken.AchievementRecord[] memory achievements = token
            .getAchievements(tokenId);
        assertEq(achievements.length, 1);
        assertEq(
            uint256(achievements[0].achievement),
            uint256(FreelancerSoulBoundToken.Achievement.FIRST_PROJECT)
        );
        assertEq(achievements[0].metadata, "First project completed");
    }

    function test_CheckAndUnlockAchievements_FirstProject() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(reputationManager);
        token.updateReputation(tokenId, 1, 80, 100e18);

        FreelancerSoulBoundToken.AchievementRecord[] memory achievements = token
            .getAchievements(tokenId);
        assertEq(achievements.length, 1);
        assertEq(
            uint256(achievements[0].achievement),
            uint256(FreelancerSoulBoundToken.Achievement.FIRST_PROJECT)
        );
    }

    function test_CheckAndUnlockAchievements_HighlyRated() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(reputationManager);
        token.updateReputation(tokenId, 5, 95, 100e18);

        FreelancerSoulBoundToken.AchievementRecord[] memory achievements = token
            .getAchievements(tokenId);
        bool hasHighlyRated = false;
        for (uint256 i = 0; i < achievements.length; i++) {
            if (
                achievements[i].achievement ==
                FreelancerSoulBoundToken.Achievement.HIGHLY_RATED
            ) {
                hasHighlyRated = true;
                break;
            }
        }
        assertTrue(hasHighlyRated);
    }

    function test_CheckAndUnlockAchievements_TopEarner() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(reputationManager);
        token.updateReputation(tokenId, 5, 80, 100000e18);

        FreelancerSoulBoundToken.AchievementRecord[] memory achievements = token
            .getAchievements(tokenId);
        bool hasTopEarner = false;
        for (uint256 i = 0; i < achievements.length; i++) {
            if (
                achievements[i].achievement ==
                FreelancerSoulBoundToken.Achievement.TOP_EARNER
            ) {
                hasTopEarner = true;
                break;
            }
        }
        assertTrue(hasTopEarner);
    }

    function test_CheckAndUnlockAchievements_SkillExpert() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(updater);
        for (uint256 i = 0; i < 5; i++) {
            token.endorseSkill(
                tokenId,
                string(abi.encodePacked("Skill", i)),
                true
            );
        }

        vm.prank(reputationManager);
        token.updateReputation(tokenId, 5, 80, 100e18); // Trigger achievement check

        FreelancerSoulBoundToken.AchievementRecord[] memory achievements = token
            .getAchievements(tokenId);
        bool hasSkillExpert = false;
        for (uint256 i = 0; i < achievements.length; i++) {
            if (
                achievements[i].achievement ==
                FreelancerSoulBoundToken.Achievement.SKILL_EXPERT
            ) {
                hasSkillExpert = true;
                break;
            }
        }
        assertTrue(hasSkillExpert);
    }

    function test_GetTokenIdByFreelancer() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        assertEq(token.getTokenIdByFreelancer(freelancer1), tokenId);
    }

    function test_GetTotalTokensMinted() public {
        assertEq(token.getTotalTokensMinted(), 0);

        vm.prank(minter);
        token.mintFreelancerToken(freelancer1, "freelancer_1");

        assertEq(token.getTotalTokensMinted(), 1);
    }

    function test_TransferFrom_Reverts() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(freelancer1);
        vm.expectRevert("SoulBound: Tokens cannot be transferred");
        token.transferFrom(freelancer1, freelancer2, tokenId);
    }

    function test_SafeTransferFrom_Reverts() public {
        vm.prank(minter);
        uint256 tokenId = token.mintFreelancerToken(
            freelancer1,
            "freelancer_1"
        );

        vm.prank(freelancer1);
        vm.expectRevert("SoulBound: Tokens cannot be transferred");
        token.safeTransferFrom(freelancer1, freelancer2, tokenId);
    }

    function test_SupportsInterface() public {
        // ERC721 interface
        assertTrue(token.supportsInterface(0x80ac58cd));
        // AccessControl interface
        assertTrue(token.supportsInterface(0x7965db0b));
    }
}
