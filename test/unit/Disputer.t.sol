// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";

import { Distributor } from "../../contracts/Distributor.sol";
import { Disputer } from "../../contracts/Disputer.sol";
import { DistributorTest } from "./Distributor.t.sol";
import { IAccessControlManager } from "../../contracts/interfaces/IAccessControlManager.sol";
import { Errors } from "../../contracts/utils/Errors.sol";

contract DisputerTest is DistributorTest {
    Disputer public disputer;

    function setUp() public override {
        super.setUp();

        // Create a dynamic array
        address[] memory disputeInitiators = new address[](1);
        disputeInitiators[0] = bob;

        disputer = new Disputer(governor, disputeInitiators, distributor);
    }

    function test_DisputeWithInsufficientBalance_shouldRevert() public {
        deal(address(distributor.disputeToken()), address(disputer), distributor.disputeAmount() - 1);

        vm.startPrank(bob);

        vm.expectRevert("ERC20: insufficient allowance");
        disputer.toggleDispute("reason");
    }

    function test_disputeWithSufficientBalance_shouldSucceed() public {
        uint256 disputeAmount = distributor.disputeAmount();
        deal(address(distributor.disputeToken()), address(disputer), disputeAmount);

        vm.startPrank(bob);
        // Check if we're still within the dispute period
        if (block.timestamp <= distributor.endOfDisputePeriod()) {
            disputer.toggleDispute("valid reason");
        } else {
            vm.expectRevert(abi.encodeWithSignature("InvalidDispute()"));
            disputer.toggleDispute("valid reason");
        }
        vm.stopPrank();
    }

    function test_disputeFromNonWhitelisted_shouldRevert() public {
        vm.startPrank(charlie);
        vm.expectRevert(Errors.NotWhitelisted.selector);
        disputer.toggleDispute("reason");
        vm.stopPrank();
    }

    function test_addToWhitelist_shouldSucceed() public {
        vm.startPrank(governor);
        disputer.addToWhitelist(charlie);
        vm.stopPrank();

        assertTrue(disputer.whitelist(charlie));
    }

    function test_removeFromWhitelist_shouldSucceed() public {
        vm.startPrank(governor);
        disputer.removeFromWhitelist(bob);
        vm.stopPrank();

        assertFalse(disputer.whitelist(bob));
    }

    function test_setDistributor_shouldSucceed() public {
        vm.startPrank(governor);

        // set up new distributor
        distributorImpl = new Distributor();
        distributor = Distributor(deployUUPS(address(distributorImpl), hex""));
        distributor.initialize(IAccessControlManager(address(accessControlManager)));

        distributor.setDisputeAmount(1e18);
        distributor.setDisputePeriod(1 days);
        distributor.setDisputeToken(angle);
        disputer.setDistributor(distributor);
        vm.stopPrank();

        assertEq(address(disputer.distributor()), address(distributor));
    }

    function test_withdrawERC20Funds_shouldSucceed() public {
        address disputeToken = address(distributor.disputeToken());
        uint256 amount = 100 * 10 ** 18; // 100 tokens
        deal(disputeToken, address(disputer), amount);

        uint256 governorBalanceBefore = IERC20(disputeToken).balanceOf(governor);

        vm.startPrank(governor);
        disputer.withdrawFunds(disputeToken, governor, amount);
        vm.stopPrank();

        uint256 governorBalanceAfter = IERC20(disputeToken).balanceOf(governor);
        assertEq(governorBalanceAfter - governorBalanceBefore, amount);
    }

    function test_withdrawETHFunds_shouldSucceed() public {
        uint256 amount = 1 ether;

        // Fund the Disputer contract with some ETH
        vm.deal(address(disputer), amount);

        uint256 governorBalanceBefore = governor.balance;

        vm.startPrank(governor);
        disputer.withdrawFunds(payable(governor), amount);
        vm.stopPrank();

        uint256 governorBalanceAfter = governor.balance;
        assertEq(governorBalanceAfter - governorBalanceBefore, amount);
        assertEq(address(disputer).balance, 0);
    }

    function test_withdrawFunds_notOwner_shouldRevert() public {
        uint256 amount = 1 ether;
        vm.deal(address(disputer), amount);

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        disputer.withdrawFunds(payable(governor), amount);
        vm.stopPrank();
    }

    function test_withdrawFunds_insufficientBalance_shouldRevert() public {
        uint256 amount = 1 ether;
        // Don't fund the contract

        vm.startPrank(governor);
        vm.expectRevert(Errors.WithdrawalFailed.selector);
        disputer.withdrawFunds(payable(governor), amount);
        vm.stopPrank();
    }
}
