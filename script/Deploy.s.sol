// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {FreelancerContract} from "../src/FreelancerContract.sol";

contract DeployScript is Script {
    function run() external returns (FreelancerContract) {
        vm.startBroadcast(); // Start broadcasting transactions
        FreelancerContract freelancerContract = new FreelancerContract();
        vm.stopBroadcast(); // Stop broadcasting
        return freelancerContract;
    }
}