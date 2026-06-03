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

    // FIX: raw strings are now hashed off-chain before being passed to the
    // contract. keccak256(abi.encodePacked(str)) is the standard pattern.
    // The human-readable strings are kept as comments for reference.
    bytes32 public ndaContentHash =
        keccak256(abi.encodePacked("This is a sample NDA content for IP protection."));
    bytes32 public anotherNdaContentHash =
        keccak256(abi.encodePacked("Another NDA"));
    bytes32 public businessSigHash =
        keccak256(abi.encodePacked("Business Owner Signature"));
    bytes32 public freelancerSigHash =
        keccak256(abi.encodePacked("Freelancer Signature"));
    bytes32 public violationReasonHash =
        keccak256(abi.encodePacked("Violation reason"));

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
        // FIX: pass bytes32 hash instead of raw string
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        assertEq(tokenId, 1);
        assertEq(ndaToken.ownerOf(tokenId), businessOwner);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(tokenId);
        // FIX: field is now contentHash, not content
        assertEq(nda.contentHash, ndaContentHash);
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
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        // FIX: pass bytes32 hash instead of raw string
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(tokenId);
        // FIX: field is now businessSignatureHash, not businessSignature
        assertEq(nda.businessSignatureHash, businessSigHash);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.SignedByBusiness)
        );
    }

    function test_SignNDAByFreelancer() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        vm.prank(freelancer);
        // FIX: pass bytes32 hash instead of raw string
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);

        // Old token should be burned
        vm.expectRevert(
            abi.encodeWithSignature("ERC721NonexistentToken(uint256)", tokenId)
        );
        ndaToken.ownerOf(tokenId);

        // New token should exist
        uint256 newTokenId = 2;
        assertEq(ndaToken.ownerOf(newTokenId), freelancer);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(newTokenId);
        // FIX: fields are now businessSignatureHash / freelancerSignatureHash
        assertEq(nda.businessSignatureHash, businessSigHash);
        assertEq(nda.freelancerSignatureHash, freelancerSigHash);
        // FIX [Obs-3]: status is now Active (not SignedByBoth) after both parties sign
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.Active)
        );
    }

    function test_CompleteWork() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);

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
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);

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
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);

        uint256 newTokenId = 2;

        vm.prank(businessOwner);
        // FIX: pass bytes32 hash instead of raw string
        ndaToken.reportViolation(newTokenId, violationReasonHash);

        NDASoulBoundToken.NDA memory nda = ndaToken.getNDA(newTokenId);
        assertEq(
            uint256(nda.status),
            uint256(NDASoulBoundToken.NDAStatus.Violated)
        );
    }

    function test_SoulBoundTransferPrevention() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.expectRevert("SoulBound: Tokens cannot be transferred");
        ndaToken.transferFrom(businessOwner, freelancer, tokenId);
    }

    function test_GetBusinessOwnerNDAs() public {
        vm.prank(businessOwner);
        uint256 tokenId1 = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        // FIX: pass bytes32 hash instead of raw string "Another NDA"
        uint256 tokenId2 = ndaToken.createNDA(
            anotherNdaContentHash,
            freelancer,
            60
        );

        uint256[] memory ndas = ndaToken.getBusinessOwnerNDAs(businessOwner);
        assertEq(ndas.length, 2);
        assertEq(ndas[0], tokenId1);
        assertEq(ndas[1], tokenId2);
    }

    function test_GetFreelancerNDAs() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);

        uint256[] memory ndas = ndaToken.getFreelancerNDAs(freelancer);
        assertEq(ndas.length, 1);
        assertEq(ndas[0], 2); // new token ID after migration
    }

    function test_IsExpired() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        assertFalse(ndaToken.isExpired(tokenId));

        vm.warp(block.timestamp + (durationDays * 1 days) + 1);

        assertTrue(ndaToken.isExpired(tokenId));
    }

    // -------------------------------------------------------------------------
    // New tests covering the audit fixes
    // -------------------------------------------------------------------------

    // [Obs-2] Expiration enforced at business signing time
    function test_SignByBusiness_RevertsIfExpired() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.warp(block.timestamp + (durationDays * 1 days) + 1);

        vm.prank(businessOwner);
        vm.expectRevert("NDAExpired");
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);
    }

    // [Obs-2] Expiration enforced at freelancer signing time
    function test_SignByFreelancer_RevertsIfExpired() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        vm.warp(block.timestamp + (durationDays * 1 days) + 1);

        vm.prank(freelancer);
        vm.expectRevert("NDAExpired");
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);
    }

    // [Obs-1] isBurned mapping is set after token migration in signByFreelancer
    function test_IsBurned_SetAfterFreelancerSigns() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(
            ndaContentHash,
            freelancer,
            durationDays
        );

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        assertFalse(ndaToken.isBurned(tokenId));

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);

        assertTrue(ndaToken.isBurned(tokenId));
    }

    // [Obs-4] getActiveBusinessOwnerNDAs filters out burned tokens
    function test_GetActiveBusinessOwnerNDAs_FiltersBurned() public {
        // Create two NDAs
        vm.prank(businessOwner);
        uint256 tokenId1 = ndaToken.createNDA(ndaContentHash, freelancer, durationDays);

        vm.prank(businessOwner);
        uint256 tokenId2 = ndaToken.createNDA(anotherNdaContentHash, freelancer, 60);

        // Sign and migrate tokenId1 — old token is burned
        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId1, businessSigHash);
        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId1, freelancerSigHash);

        // tokenId1 is now burned; tokenId2 is still active
        uint256[] memory active = ndaToken.getActiveBusinessOwnerNDAs(businessOwner);
        assertEq(active.length, 1);
        assertEq(active[0], tokenId2);
    }

    // [Obs-1] Empty hash reverts on createNDA
    function test_CreateNDA_RevertsOnZeroHash() public {
        vm.prank(businessOwner);
        vm.expectRevert("EmptyContentHash");
        ndaToken.createNDA(bytes32(0), freelancer, durationDays);
    }

    // [Obs-1] Empty signature hash reverts on signNDAByBusiness
    function test_SignByBusiness_RevertsOnZeroHash() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(ndaContentHash, freelancer, durationDays);

        vm.prank(businessOwner);
        vm.expectRevert("EmptySignatureHash");
        ndaToken.signNDAByBusiness(tokenId, bytes32(0));
    }

    // [Obs-1] Empty reason hash reverts on reportViolation
    function test_ReportViolation_RevertsOnZeroHash() public {
        vm.prank(businessOwner);
        uint256 tokenId = ndaToken.createNDA(ndaContentHash, freelancer, durationDays);

        vm.prank(businessOwner);
        ndaToken.signNDAByBusiness(tokenId, businessSigHash);

        vm.prank(freelancer);
        ndaToken.signNDAByFreelancer(tokenId, freelancerSigHash);

        vm.prank(businessOwner);
        vm.expectRevert("EmptyReasonHash");
        ndaToken.reportViolation(2, bytes32(0));
    }
}
