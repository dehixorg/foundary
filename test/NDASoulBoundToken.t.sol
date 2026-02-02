// test/NDASoulBoundToken.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {NDASoulBoundToken} from "../src/NDASoulBoundToken.sol";

contract NDASoulBoundTokenTest is Test {
    NDASoulBoundToken public ndaToken;

    address public admin;
    address public businessOwner;
    address public freelancer;

    string public ndaContent =
        "This is a sample NDA content for IP protection.";
    string public businessSignature = "Business Owner Signature";
    string public freelancerSignature = "Freelancer Signature";
    uint256 public durationDays = 30;

    function setUp() public {
        ndaToken = new NDASoulBoundToken();

        admin = makeAddr("admin");
        businessOwner = makeAddr("businessOwner");
        freelancer = makeAddr("freelancer");

        // Grant roles
        ndaToken.grantRole(ndaToken.ADMIN_ROLE(), admin);
        ndaToken.grantRole(ndaToken.BUSINESS_OWNER_ROLE(), businessOwner);
        ndaToken.grantRole(ndaToken.FREELANCER_ROLE(), freelancer);
    }

    function test_Constructor() public {
        assertEq(ndaToken.name(), "NDASoulBoundToken");
        assertEq(ndaToken.symbol(), "NDASBT");
        assertTrue(ndaToken.hasRole(ndaToken.ADMIN_ROLE(), address(this)));
    }

    function test_CreateNDA() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        assertEq(tokenId, 1);
        assertEq(ndaToken.ownerOf(tokenId), businessOwner);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(tokenId);
        assertEq(nda.content, ndaContent);
        assertEq(nda.businessOwner, businessOwner);
        assertEq(nda.freelancer, freelancer);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.Draft)
        );
        assertEq(nda.expirationTime, block.timestamp + (durationDays * 1 days));
    }

    function test_SignNDAByBusiness() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSignature);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(tokenId);
        assertEq(nda.businessSignature, businessSignature);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.SignedByBusiness)
        );
    }

    function test_SignNDAByFreelancer() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSignature);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSignature);

        // Old token should be burned
        vm.expectRevert(
            abi.encodeWithSignature("ERC721NonexistentToken(uint256)", tokenId)
        );
        ndaToken.ownerOf(tokenId);

        // New token should exist
        uint256 newTokenId = 2;
        assertEq(ndaToken.ownerOf(newTokenId), freelancer);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(newTokenId);
        assertEq(nda.businessSignature, businessSignature);
        assertEq(nda.freelancerSignature, freelancerSignature);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.SignedByBoth)
        );
    }

    function test_CompleteWork() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSignature);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSignature);

        uint256 newTokenId = 2;

        vm.prank(freelancer);
        ndaToken.completeWork(newTokenId);

        // Token should be burned
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC721NonexistentToken(uint256)",
                newTokenId
            )
        );
        ndaToken.ownerOf(newTokenId);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(newTokenId);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.Completed)
        );
        assertTrue(nda.burned);
    }

    function test_CheckAndBurnExpired() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSignature);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSignature);

        uint256 newTokenId = 2;

        // Fast forward time past expiration
        vm.warp(block.timestamp + (durationDays * 1 days) + 1);

        ndaToken.checkAndBurnExpired(newTokenId);

        // Token should be burned
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC721NonexistentToken(uint256)",
                newTokenId
            )
        );
        ndaToken.ownerOf(newTokenId);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(newTokenId);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.Expired)
        );
        assertTrue(nda.burned);
    }

    function test_ReportViolation() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSignature);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSignature);

        uint256 newTokenId = 2;

        vm.prank(businessOwner);
        ndaToken.reportViolation(newTokenId, "Violation reason");

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(newTokenId);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.Violated)
        );
    }

    function test_SoulBoundTransferPrevention() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.expectRevert("SoulBound: Tokens cannot be transferred");
        ndaToken.transferFrom(businessOwner, freelancer, tokenId);
    }

    function test_GetBusinessOwnerNDAs() public {
        vm.prank(businessOwner);
        uint256 tokenId1 = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        uint256 tokenId2 = ndaToken.createNDA("Another NDA", freelancer, 60);

        uint256[] memory ndas = ndaToken.getBusinessOwnerNDAs(businessOwner);
        assertEq(ndas.length, 2);
        assertEq(ndas[0], tokenId1);
        assertEq(ndas[1], tokenId2);
    }

    function test_GetFreelancerNDAs() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSignature);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSignature);

        uint256[] memory ndas = ndaToken.getFreelancerNDAs(freelancer);
        assertEq(ndas.length, 1);
        assertEq(ndas[0], 2); // New token ID
    }

    function test_IsExpired() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContent,
            freelancer,
            durationDays
        );

        assertFalse(ndaToken.isExpired(tokenId));

        vm.warp(block.timestamp + (durationDays * 1 days) + 1);

        assertTrue(ndaToken.isExpired(tokenId));
    }
}
