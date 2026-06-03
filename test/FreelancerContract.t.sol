// test/FreelancerContract.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FreelancerContract} from "../src/FreelancerContract.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

contract FreelancerContractTest is Test {
    FreelancerContract public freelancerContract;
    MockERC20 public mockToken;
    StakingRewards public stakingContract;

    address public owner;
    address public business;
    address public freelancer;
    address public oracle1;
    address public oracle2;
    address public oracle3;

    function setUp() public {
        // 1. Deploy a mock token for the tests
        mockToken = new MockERC20("Mock Token", "MTK");

        // 2. Deploy the StakingRewards contract
        stakingContract = new StakingRewards(address(mockToken), address(mockToken));

        // 3. Deploy the FreelancerContract with the staking contract's address
        freelancerContract = new FreelancerContract(address(stakingContract));

        // Set up the addresses for the tests
        owner = freelancerContract.getOwner();
        business = makeAddr("business");
        freelancer = makeAddr("freelancer");
        oracle1 = makeAddr("oracle1");
        oracle2 = makeAddr("oracle2");
        oracle3 = makeAddr("oracle3");

        // Give the business some mock tokens to use in tests
        mockToken.mint(business, 1_000_000e18);

        // --- STAKING SETUP FOR ORACLES ---
        // Give the oracles tokens to stake
        mockToken.mint(oracle1, 100e18);
        mockToken.mint(oracle2, 100e18);
        mockToken.mint(oracle3, 100e18);

        // Oracles must approve the staking contract to spend their tokens and then stake
        vm.startPrank(oracle1);
        mockToken.approve(address(stakingContract), 100e18);
        stakingContract.stake(100e18);
        vm.stopPrank();

        vm.startPrank(oracle2);
        mockToken.approve(address(stakingContract), 100e18);
        stakingContract.stake(100e18);
        vm.stopPrank();

        vm.startPrank(oracle3);
        mockToken.approve(address(stakingContract), 100e18);
        stakingContract.stake(100e18);
        vm.stopPrank();
    }

    function _setupEscrow(string memory escrowId) internal {
        vm.prank(owner);
        freelancerContract.addOracle(oracle1);
        vm.prank(owner);
        freelancerContract.addOracle(oracle2);
        vm.prank(owner);
        freelancerContract.addOracle(oracle3);

        address[] memory oracles = new address[](3);
        oracles[0] = oracle1;
        oracles[1] = oracle2;
        oracles[2] = oracle3;
        vm.prank(business);
        freelancerContract.createEscrow(escrowId, oracles, freelancer, address(mockToken));
    }

    function testAddBusiness() public {
        vm.prank(owner);
        freelancerContract.addBusiness("business-1", business);

        (string memory businessId, address businessAddress) = freelancerContract.s_businesses("business-1");
        
        assertEq(businessId, "business-1");
        assertEq(businessAddress, business);
    }

    function testCreateProject() public {
        vm.prank(owner);
        freelancerContract.createProject("project-1");
        (string memory projectId, bool isActive) = freelancerContract.s_projects("project-1");
        assertTrue(isActive);
        assertEq(projectId, "project-1");
    }

    function testCreateAndDepositEscrow() public {
        string memory escrowId = "escrow-1";
        uint256 depositAmount = 100e18;
        _setupEscrow(escrowId);

        vm.prank(business);
        mockToken.approve(address(freelancerContract), depositAmount);
        vm.prank(business);
        freelancerContract.depositFunds(depositAmount, escrowId);

        ( , , , , uint256 deposited, ) = freelancerContract.getEscrow(escrowId);
        assertEq(deposited, depositAmount);
        assertEq(mockToken.balanceOf(address(freelancerContract)), depositAmount);
    }

    function testReleaseFunds() public {
        string memory escrowId = "escrow-1";
        uint256 depositAmount = 100e18;
        _setupEscrow(escrowId);

        vm.prank(business);
        mockToken.approve(address(freelancerContract), depositAmount);
        vm.prank(business);
        freelancerContract.depositFunds(depositAmount, escrowId);

        vm.prank(oracle1);
        freelancerContract.vote(escrowId, true);
        vm.prank(oracle2);
        freelancerContract.vote(escrowId, true);

        vm.prank(business);
        freelancerContract.releaseFunds(escrowId);

        ( , , , , uint256 finalAmount, ) = freelancerContract.getEscrow(escrowId);
        assertEq(finalAmount, 0);
        assertEq(mockToken.balanceOf(freelancer), depositAmount);
    }

    function testRefundFunds() public {
        string memory escrowId = "escrow-1";
        uint256 depositAmount = 100e18;
        _setupEscrow(escrowId);

        vm.prank(business);
        mockToken.approve(address(freelancerContract), depositAmount);
        vm.prank(business);
        freelancerContract.depositFunds(depositAmount, escrowId);

        vm.prank(oracle1);
        freelancerContract.vote(escrowId, false);
        vm.prank(oracle2);
        freelancerContract.vote(escrowId, false);

        vm.prank(freelancer);
        freelancerContract.refundFunds(escrowId);

        ( , , , , uint256 finalAmount, ) = freelancerContract.getEscrow(escrowId);
        assertEq(finalAmount, 0);
        assertEq(mockToken.balanceOf(business), 1_000_000e18);
    }
}