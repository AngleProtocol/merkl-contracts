// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Distributor } from "../../contracts/Distributor.sol";
import { Disputer } from "../../contracts/Disputer.sol";
import { Fixture, IERC20 } from "./Fixture.t.sol";

contract DisputerTest is Fixture {
    Disputer public disputer;
    Distributor public distributor;

    address public constant DEFAULT_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address public constant ASTARZKEVM_DISTRIBUTOR = 0xA7c167f58833c5e25848837f45A1372491A535eD;
    address public constant ZKSYNC_ERA_DISTRIBUTOR = 0xe117ed7Ef16d3c28fCBA7eC49AFAD77f451a6a21;

    function setUp() public override {
        super.setUp();
        address distributorAddress;
        if (block.chainid == 3776) {
            // AstarZkEVM
            distributorAddress = ASTARZKEVM_DISTRIBUTOR;
        } else if (block.chainid == 324) {
            // zkSync Era
            distributorAddress = ZKSYNC_ERA_DISTRIBUTOR;
        } else {
            // Default
            distributorAddress = DEFAULT_DISTRIBUTOR;
        }
        distributor = Distributor(distributorAddress);

        // Create a dynamic array
        address[] memory disputeInitiators = new address[](1);
        disputeInitiators[0] = bob;

        disputer = new Disputer(alice, disputeInitiators, distributor);
    }

    function test_disputeWithInsufficientBalance_shouldRevert() public {
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
        vm.expectRevert(Disputer.NotWhitelisted.selector);
        disputer.toggleDispute("reason");
        vm.stopPrank();
    }

    function test_addToWhitelist_shouldSucceed() public {
        vm.startPrank(alice);
        disputer.addToWhitelist(charlie);
        vm.stopPrank();

        assertTrue(disputer.whitelist(charlie));
    }

    function test_removeFromWhitelist_shouldSucceed() public {
        vm.startPrank(alice);
        disputer.removeFromWhitelist(bob);
        vm.stopPrank();

        assertFalse(disputer.whitelist(bob));
    }

    function test_setDistributor_shouldSucceed() public {
        Distributor newDistributor = new Distributor();

        vm.startPrank(alice);
        disputer.setDistributor(newDistributor);
        vm.stopPrank();

        assertEq(address(disputer.distributor()), address(newDistributor));
    }

    function test_withdrawERC20Funds_shouldSucceed() public {
        address disputeToken = address(distributor.disputeToken());
        uint256 amount = 100 * 10 ** 18; // 100 tokens
        deal(disputeToken, address(disputer), amount);

        uint256 charlieBalanceBefore = IERC20(disputeToken).balanceOf(charlie);

        vm.startPrank(alice);
        disputer.withdrawFunds(disputeToken, charlie, amount);
        vm.stopPrank();

        uint256 charlieBalanceAfter = IERC20(disputeToken).balanceOf(charlie);
        assertEq(charlieBalanceAfter - charlieBalanceBefore, amount);
    }

    function test_withdrawETHFunds_shouldSucceed() public {
        uint256 amount = 1 ether;

        // Fund the Disputer contract with some ETH
        vm.deal(address(disputer), amount);

        uint256 charlieBalanceBefore = charlie.balance;

        vm.startPrank(alice);
        disputer.withdrawFunds(payable(charlie), amount);
        vm.stopPrank();

        uint256 charlieBalanceAfter = charlie.balance;
        assertEq(charlieBalanceAfter - charlieBalanceBefore, amount);
        assertEq(address(disputer).balance, 0);
    }

    function test_withdrawFunds_notOwner_shouldRevert() public {
        uint256 amount = 1 ether;
        vm.deal(address(disputer), amount);

        vm.startPrank(charlie);
        vm.expectRevert("Ownable: caller is not the owner");
        disputer.withdrawFunds(payable(charlie), amount);
        vm.stopPrank();
    }

    function test_withdrawFunds_insufficientBalance_shouldRevert() public {
        uint256 amount = 1 ether;
        // Don't fund the contract

        vm.startPrank(alice);
        vm.expectRevert(Disputer.WithdrawalFailed.selector);
        disputer.withdrawFunds(payable(charlie), amount);
        vm.stopPrank();
    }
}
