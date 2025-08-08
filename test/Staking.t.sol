// test/Staking.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FreelancerContract} from "../src/FreelancerContract.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

contract StakingTest is Test {
    FreelancerContract public freelancerContract;
    MockERC20 public mockToken;
    StakingRewards public stakingContract;

    address public owner;
    address public oracle1;

    function setUp() public {
        mockToken = new MockERC20("Mock Token", "MTK");
        stakingContract = new StakingRewards(address(mockToken), address(mockToken));
        freelancerContract = new FreelancerContract(address(stakingContract));

        owner = freelancerContract.getOwner();
        oracle1 = makeAddr("oracle1");

        // Mint tokens for the oracle to stake
        mockToken.mint(oracle1, 1000e18);
    }

    function testStakeTokens() public {
        vm.startPrank(oracle1);
        mockToken.approve(address(stakingContract), 500e18);
        stakingContract.stake(500e18);
        vm.stopPrank();

        assertEq(stakingContract.balanceOf(oracle1), 500e18, "Staking balance should be 500");
        assertEq(mockToken.balanceOf(address(stakingContract)), 500e18, "Staking contract token balance should be 500");
    }

    // RENAMED FUNCTION
    function test_RevertIf_AddOracleWithoutStake() public {
        vm.prank(owner);
        vm.expectRevert("OracleMustHaveStake");
        freelancerContract.addOracle(oracle1);
    }

    function testSuccess_AddOracleWithStake() public {
        vm.startPrank(oracle1);
        mockToken.approve(address(stakingContract), 100e18);
        stakingContract.stake(100e18);
        vm.stopPrank();

        vm.prank(owner);
        freelancerContract.addOracle(oracle1);

        assertTrue(freelancerContract.s_oracles(oracle1), "Oracle should be successfully added");
    }

    function testWithdrawTokens() public {
        vm.startPrank(oracle1);
        mockToken.approve(address(stakingContract), 500e18);
        stakingContract.stake(500e18);
        
        stakingContract.withdraw(200e18);
        vm.stopPrank();

        assertEq(stakingContract.balanceOf(oracle1), 300e18, "Staking balance should be 300");
        assertEq(mockToken.balanceOf(address(stakingContract)), 300e18, "Staking contract token balance should be 300");
    }
}