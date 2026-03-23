// script/DeployAll.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MyToken} from "../src/Token.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {FreelancerContract} from "../src/FreelancerContract.sol";
import {FreelancerSoulBoundToken} from "../src/FreelancerSoulBoundToken.sol";
import {NDASoulBoundToken} from "../src/NDASoulBoundToken.sol";

contract DeployAll is Script {
    function run() external returns (FreelancerContract, StakingRewards, MyToken, FreelancerSoulBoundToken, NDASoulBoundToken           ) {
        vm.startBroadcast();

        // 1. Deploy the ERC20 Token first.
        // This token can be used for both staking and rewards.
        MyToken token = new MyToken();

        // 2. Deploy the StakingRewards contract.
        // It needs to know which token to use for staking and which for rewards.
        // We'll use the same token for both in this example.
        StakingRewards stakingContract = new StakingRewards(address(token), address(token));

        // 3. Deploy the FreelancerContract.
        // It needs the address of the StakingRewards contract to enforce staking rules.
        FreelancerContract freelancerContract = new FreelancerContract(address(stakingContract));

        // 4. Deploy the FreelancerSoulBoundToken and NDASoulBoundToken.
        FreelancerSoulBoundToken freelancerSBT = new FreelancerSoulBoundToken();
        NDASoulBoundToken ndaSBT = new NDASoulBoundToken();

        vm.stopBroadcast();
        return (freelancerContract, stakingContract, token, freelancerSBT, ndaSBT);
    }
}