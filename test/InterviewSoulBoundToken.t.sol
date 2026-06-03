
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {InterviewSoulboundToken} from "../src/InterviewSoulBoundToken.sol";

contract InterviewSoulboundTokenTest is Test {
    InterviewSoulboundToken public sbt;

    address public participant;
    address public stranger;
    address public interviewer;

    function setUp() public {
        address[] memory interviewers = new address[](1);
        interviewers[0] = makeAddr("interviewer");
        sbt = new InterviewSoulboundToken(interviewers);

        participant = makeAddr("participant");
        stranger = makeAddr("stranger");
        interviewer = makeAddr("interviewer");
    }

    function testMintSBTAndGetDetails() public {
        string[] memory skills = new string[](2);
        skills[0] = "Solidity";
        skills[1] = "Testing";

        uint256[] memory skillIds = new uint256[](2);
        skillIds[0] = 101;
        skillIds[1] = 102;

        // ✅ Mint as interviewer
        vm.prank(interviewer);
        uint256 tokenId = sbt.mintSBT(
            participant,
            1234,
            5678,
            skills,
            skillIds,
            "Excellent interview performance"
        );

        assertEq(tokenId, 1);

        (
            uint256 participantId,
            uint256 interviewerId,
            string[] memory gotSkills,
            uint256[] memory gotSkillIds,
            string memory review,
            uint256 timestamp
        ) = sbt.getTokenDetails(tokenId);

        assertEq(participantId, 1234);
        assertEq(interviewerId, 5678);
        assertEq(gotSkills.length, 2);
        assertEq(gotSkillIds[0], 101);
        assertEq(gotSkillIds[1], 102);
        assertEq(review, "Excellent interview performance");
        assertTrue(timestamp > 0);
    }

    function testNonTransferable() public {
        string[] memory skills = new string[](1);
        skills[0] = "Solidity";

        uint256[] memory skillIds = new uint256[](1);
        skillIds[0] = 1;

        // ✅ Mint as interviewer
        vm.prank(interviewer);
        uint256 tokenId = sbt.mintSBT(
            participant,
            1,
            1,
            skills,
            skillIds,
            "Non-transferable check"
        );

        vm.prank(participant);
        vm.expectRevert(bytes("Soulbound: transfer disabled"));
        sbt.transferFrom(participant, stranger, tokenId);
    }

    function testApprovalDisabled() public {
        string[] memory skills = new string[](1);
        skills[0] = "Security";

        uint256[] memory skillIds = new uint256[](1);
        skillIds[0] = 5;

        // ✅ Mint as interviewer
        vm.prank(interviewer);
        uint256 tokenId = sbt.mintSBT(
            participant,
            42,
            43,
            skills,
            skillIds,
            "Approval disabled check"
        );

        vm.prank(participant);
        vm.expectRevert(bytes("Soulbound: approval disabled"));
        sbt.approve(stranger, tokenId);

        vm.prank(participant);
        vm.expectRevert(bytes("Soulbound: approval for all disabled"));
        sbt.setApprovalForAll(stranger, true);
    }

    function testOnlyInterviewerCanMint() public {
        string[] memory skills = new string[](1);
        skills[0] = "Solidity";

        uint256[] memory skillIds = new uint256[](1);
        skillIds[0] = 1;

        vm.prank(stranger);
        vm.expectRevert(bytes("Not an authorized interviewer"));
        sbt.mintSBT(
            participant,
            1,
            1,
            skills,
            skillIds,
            "Unauthorized mint"
        );
    }
}

