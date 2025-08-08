// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MyToken} from "../src/Token.sol";

contract DeployOurToken is Script {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether; // 1 million tokens with 18 decimal places

    function run() external returns (MyToken) {
        vm.startBroadcast();
        MyToken myToken = new MyToken();

        address recipient = 0xdCad3a6d3569DF655070DEd06cb7A1b2Ccd1D3AF;
        uint256 mintAmount = 1000 * (10 ** myToken.decimals());
        myToken.mint(recipient, mintAmount);
        console.log("Minted", mintAmount, "tokens to", recipient);

        address burnAddress = recipient;
        uint256 burnAmount = 500 * (10 ** myToken.decimals());
        myToken.burn(burnAddress, burnAmount);
        console.log("Burned", burnAmount, "tokens from", burnAddress);

        vm.stopBroadcast();
        return myToken;
    }
}
