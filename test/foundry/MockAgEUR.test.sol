// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import "../../contracts/example/MockAgEUR.sol";

contract MockAgEURTest is Test {
    address payable public alice;
    address payable public bob;
    MockAgEUR public token;

    function setUp() public {
        /** Create users */
        alice = payable(address(uint160(uint256(keccak256(abi.encodePacked("alice"))))));
        bob = payable(address(uint160(uint256(keccak256(abi.encodePacked("bob"))))));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        /** Add labels to users */
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        /** Deploy mock token */
        token = new MockAgEUR();
    }

    function destroy() public returns (uint256) {
        selfdestruct(payable(0));
        return 1;
    }

    function testDeployment() public payable {
        assertEq(token.owner(), address(this));
        assertEq(token.name(), "Mock Token");
        assertEq(token.symbol(), "MTK");
    }

    function testUsersBalance() public payable {
        assertEq(alice.balance, 10 ether);
        assertEq(bob.balance, 10 ether);
    }

    function testMint1() public {
        token.mint(alice, 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf((bob)), 0);
    }

    function testMintTransfer(uint256 _amount, uint256 _toTransfer) public {
        vm.assume(_amount <= 1000000);
        vm.assume(_toTransfer <= _amount);
        token.mint(alice, _amount);
        assertEq(token.balanceOf(alice), _amount);
        assertEq(token.balanceOf((bob)), 0);
        vm.prank(alice);
        token.approve(address(this), 1000000);
        vm.stopPrank();
        token.transferFrom(alice, bob, _toTransfer);
        assertEq(token.balanceOf(alice), _amount - _toTransfer);
        assertEq(token.balanceOf((bob)), _toTransfer);
    }

    // ================================ TEST IN FORK ===============================

    function testMainnetBalance() public {
        uint256 mainnetForkId = vm.createFork("mainnet", 15_638_436);
        vm.selectFork(mainnetForkId);
        assertEq(address(0).balance, 11476070351253859226921);
    }

    function testPolygonBalance() public {
        uint256 polygonForkId = vm.createFork("polygon", 33_710_302);
        vm.selectFork(polygonForkId);
        assertEq(address(0).balance, 58583241519411840754757);
    }

    function testBalance() public {
        assertEq(address(0).balance, 0);
    }
}
