// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {FreelancerContract} from "../src/FreelancerContract.sol";

contract DeployFreelancerContract is Script {
    function run() external returns (FreelancerContract) {
        vm.startBroadcast();
        FreelancerContract freelancerContract = new FreelancerContract();
        vm.stopBroadcast();
        return freelancerContract;
    }
}
