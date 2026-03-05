// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {

    constructor() ERC20("MockToken","MTK") {
        _mint(msg.sender, 1000000 ether);
    }

}

contract EscrowContractTest is Test {

    EscrowContract escrow;
    MockToken token;

    address client = address(1);
    address freelancer = address(2);
    address admin = address(this);

    function setUp() public {

        escrow = new EscrowContract();
        token = new MockToken();

        token.transfer(client, 1000 ether);

    }

    function testCreateEscrow() public {

        vm.prank(client);

        escrow.createEscrow(
            "job1",
            freelancer
        );

        (
            address c,
            address f,
            address[] memory tokens,
            bool active
        ) = escrow.getEscrow("job1");

        assertEq(c, client);
        assertEq(f, freelancer);
        assertEq(active, true);
        assertEq(tokens.length, 0);
    }

    function testDepositToken() public {

        vm.startPrank(client);

        escrow.createEscrow("job1", freelancer);

        token.approve(address(escrow), 100 ether);

        escrow.depositToken(
            "job1",
            address(token),
            100 ether
        );

        vm.stopPrank();

        uint256 balance = escrow.getTokenBalance(
            "job1",
            address(token)
        );

        assertEq(balance, 100 ether);
    }

    function testReleaseFunds() public {

        vm.startPrank(client);

        escrow.createEscrow("job1", freelancer);

        token.approve(address(escrow), 100 ether);

        escrow.depositToken(
            "job1",
            address(token),
            100 ether
        );

        escrow.releaseFunds("job1");

        vm.stopPrank();

        assertEq(
            token.balanceOf(freelancer),
            100 ether
        );
    }

    function testAdminResolveDispute() public {

        vm.startPrank(client);

        escrow.createEscrow("job1", freelancer);

        token.approve(address(escrow), 100 ether);

        escrow.depositToken(
            "job1",
            address(token),
            100 ether
        );

        vm.stopPrank();

        escrow.resolveDispute(
            "job1",
            true
        );

        assertEq(
            token.balanceOf(freelancer),
            100 ether
        );
    }

}