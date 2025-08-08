// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FreelancerContract} from "../../src/FreelancerContract.sol";

contract AdvancedFuzzTest is Test {
    FreelancerContract public freelancerContract;
    address public owner;

    function setUp() public {
        freelancerContract = new FreelancerContract();
        owner = freelancerContract.getOwner();
    }

    // This test will throw random addresses at the createEscrow function
    // to ensure it never reverts with valid inputs.
    function testFuzz_CreateEscrow(address oracle1, address oracle2, address oracle3, address freelancer) public {
        // Constrain the random data to be valid addresses
        vm.assume(oracle1 != address(0) && oracle1 != owner);
        vm.assume(oracle2 != address(0) && oracle2 != owner);
        vm.assume(oracle3 != address(0) && oracle3 != owner);
        vm.assume(freelancer != address(0));

        // Setup: Owner adds the valid oracles
        vm.prank(owner);
        freelancerContract.addOracle(oracle1);
        vm.prank(owner);
        freelancerContract.addOracle(oracle2);
        vm.prank(owner);
        freelancerContract.addOracle(oracle3);

        // Test: createEscrow should not revert with these valid inputs
        address[] memory oracles = new address[](3);
        oracles[0] = oracle1;
        oracles[1] = oracle2;
        oracles[2] = oracle3;

        // The business (funder) is a new random address each time
        address business = makeAddr("randomBusiness");
        vm.prank(business);
        freelancerContract.createEscrow("fuzz-escrow", oracles, freelancer, address(0)); // Token address can be 0 for this test
    }
}