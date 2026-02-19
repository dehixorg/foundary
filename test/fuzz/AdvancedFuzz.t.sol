// test/fuzz/AdvancedFuzz.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FreelancerContract} from "../../src/FreelancerContract.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {StakingRewards} from "../../src/StakingRewards.sol";

contract AdvancedFuzzTest is Test {
    FreelancerContract public freelancerContract;
    address public owner;
    MockERC20 public mockToken;
    StakingRewards public stakingContract;

    function setUp() public {
        mockToken = new MockERC20("Mock Token", "MTK");
        stakingContract = new StakingRewards(address(mockToken), address(mockToken));
        freelancerContract = new FreelancerContract(address(stakingContract));
        owner = freelancerContract.getOwner();
    }

    function testFuzz_CreateEscrow(address oracle1, address oracle2, address oracle3, address freelancer) public {
        vm.assume(oracle1 != address(0) && oracle1 != owner);
        vm.assume(oracle2 != address(0) && oracle2 != owner && oracle2 != oracle1);
        vm.assume(oracle3 != address(0) && oracle3 != owner && oracle3 != oracle1 && oracle3 != oracle2);
        vm.assume(freelancer != address(0));

        // --- STAKING SETUP FOR ORACLES (FUZZ) ---
        // Mint, APPROVE, and stake for each oracle
        mockToken.mint(oracle1, 1e18);
        vm.startPrank(oracle1);
        mockToken.approve(address(stakingContract), 1e18); // <-- FIX
        stakingContract.stake(1e18);
        vm.stopPrank();

        mockToken.mint(oracle2, 1e18);
        vm.startPrank(oracle2);
        mockToken.approve(address(stakingContract), 1e18); // <-- FIX
        stakingContract.stake(1e18);
        vm.stopPrank();

        mockToken.mint(oracle3, 1e18);
        vm.startPrank(oracle3);
        mockToken.approve(address(stakingContract), 1e18); // <-- FIX
        stakingContract.stake(1e18);
        vm.stopPrank();

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

        address business = makeAddr("randomBusiness");
        vm.prank(business);
        freelancerContract.createEscrow("fuzz-escrow", oracles, freelancer, address(mockToken));
    }
}