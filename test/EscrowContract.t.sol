// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/EscrowContract.sol";
import {Test} from "forge-std/Test.sol";
//import {FreelancerContract} from "../src/FreelancerContract.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract EscrowContractTest is Test {

    EscrowContract public escrowContract;

    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public owner;
    address public business;
    address public freelancer;

    string public escrowId = "escrow-1";

    function setUp() public {

        escrowContract = new EscrowContract();

        owner = escrowContract.getOwner();

        business = makeAddr("business");
        freelancer = makeAddr("freelancer");

        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");

        tokenA.mint(business, 1_000_000e18);
        tokenB.mint(business, 1_000_000e18);
    }

    function testCreateEscrow() public {

        vm.prank(business);

        escrowContract.createEscrow(
            escrowId,
            freelancer
        );

        (
            address client,
            address free,
            ,
            bool active
        ) = escrowContract.getEscrow(escrowId);

        assertEq(client, business);
        assertEq(free, freelancer);
        assertTrue(active);
    }

    function testDepositMultipleTokens() public {

        vm.startPrank(business);

        escrowContract.createEscrow(
            escrowId,
            freelancer
        );

        tokenA.approve(address(escrowContract), 100e18);
        tokenB.approve(address(escrowContract), 50e18);

        escrowContract.depositToken(
            escrowId,
            address(tokenA),
            100e18
        );

        escrowContract.depositToken(
            escrowId,
            address(tokenB),
            50e18
        );

        vm.stopPrank();

        uint256 balanceA = escrowContract.getTokenBalance(
            escrowId,
            address(tokenA)
        );

        uint256 balanceB = escrowContract.getTokenBalance(
            escrowId,
            address(tokenB)
        );

        assertEq(balanceA, 100e18);
        assertEq(balanceB, 50e18);
    }

    function testReleaseFundsToFreelancer() public {

        vm.startPrank(business);

        escrowContract.createEscrow(
            escrowId,
            freelancer
        );

        tokenA.approve(address(escrowContract), 100e18);

        escrowContract.depositToken(
            escrowId,
            address(tokenA),
            100e18
        );

        escrowContract.releaseFunds(
            escrowId
        );

        vm.stopPrank();

        assertEq(
            tokenA.balanceOf(freelancer),
            100e18
        );
    }

    function testRefundFundsToClient() public {

        vm.startPrank(business);

        escrowContract.createEscrow(
            escrowId,
            freelancer
        );

        tokenA.approve(address(escrowContract), 200e18);

        escrowContract.depositToken(
            escrowId,
            address(tokenA),
            200e18
        );

        vm.stopPrank();

        vm.prank(freelancer);

        escrowContract.refundFunds(
            escrowId
        );

        assertEq(
            tokenA.balanceOf(business),
            1_000_000e18
        );
    }

    function testAdminResolveDisputeRelease() public {

        vm.startPrank(business);

        escrowContract.createEscrow(
            escrowId,
            freelancer
        );

        tokenA.approve(address(escrowContract), 150e18);

        escrowContract.depositToken(
            escrowId,
            address(tokenA),
            150e18
        );

        vm.stopPrank();

        vm.prank(owner);

        escrowContract.resolveDispute(
            escrowId,
            true
        );

        assertEq(
            tokenA.balanceOf(freelancer),
            150e18
        );
    }

    function testAdminResolveDisputeRefund() public {

        vm.startPrank(business);

        escrowContract.createEscrow(
            escrowId,
            freelancer
        );

        tokenA.approve(address(escrowContract), 150e18);

        escrowContract.depositToken(
            escrowId,
            address(tokenA),
            150e18
        );

        vm.stopPrank();

        vm.prank(owner);

        escrowContract.resolveDispute(
            escrowId,
            false
        );

        assertEq(
            tokenA.balanceOf(business),
            1_000_000e18
        );
    }
}