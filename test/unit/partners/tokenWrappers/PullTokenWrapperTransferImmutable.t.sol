// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { PullTokenWrapperTransferImmutable } from "../../../../contracts/partners/tokenWrappers/PullTokenWrapperTransferImmutable.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient } from "./TokenWrapperMocks.sol";

/// @dev Base contract tests (mint, setHolder, toggleAllowance, afterTokenTransfer, setFeeRecipient,
/// decimals, edge cases) are covered via PullTokenWrapperAllowImmutable.t.sol since they test
/// shared logic in PullTokenWrapperImmutableBase. This file only tests Transfer-specific behavior.

contract PullTokenWrapperTransferImmutableTest is Fixture {
    PullTokenWrapperTransferImmutable public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new PullTokenWrapperTransferImmutable(address(angle), address(creator), alice);

        mockDistributor.setWrapper(address(wrapper));

        // Fund the wrapper contract with underlying tokens (tokens are pulled from the contract itself)
        angle.mint(address(wrapper), 1000 ether);
    }
}

contract Test_PullTokenWrapperTransferImmutable_Constructor is PullTokenWrapperTransferImmutableTest {
    function test_Success() public {
        assertEq(wrapper.name(), string(abi.encodePacked(angle.name(), " (wrapped)")));
        assertEq(wrapper.symbol(), angle.symbol());
        assertEq(wrapper.token(), address(angle));
        assertEq(wrapper.holder(), alice);
        assertEq(address(wrapper.accessControlManager()), address(accessControlManager));
        assertEq(wrapper.distributor(), address(mockDistributor));
        assertEq(wrapper.distributionCreator(), address(creator));
        assertEq(wrapper.decimals(), angle.decimals());
        assertEq(wrapper.feeRecipient(), address(mockFeeRecipient));
    }
}

contract Test_PullTokenWrapperTransferImmutable_BeforeTokenTransfer is PullTokenWrapperTransferImmutableTest {
    function setUp() public override {
        super.setUp();

        // Mint wrapper tokens and transfer to distributor
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);
    }

    function test_Success_TransferFromDistributorSendsTokens() public {
        uint256 bobBalanceBefore = angle.balanceOf(bob);
        uint256 wrapperBalanceBefore = angle.balanceOf(address(wrapper));

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        // Bob should receive underlying tokens (sent from wrapper contract)
        assertEq(angle.balanceOf(bob), bobBalanceBefore + 20 ether);
        // Wrapper contract balance should decrease
        assertEq(angle.balanceOf(address(wrapper)), wrapperBalanceBefore - 20 ether);
        // Bob should not keep wrapper tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToFeeRecipientSendsTokens() public {
        uint256 feeRecipientBalanceBefore = angle.balanceOf(address(mockFeeRecipient));
        uint256 wrapperBalanceBefore = angle.balanceOf(address(wrapper));

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(angle.balanceOf(address(mockFeeRecipient)), feeRecipientBalanceBefore + 10 ether);
        assertEq(angle.balanceOf(address(wrapper)), wrapperBalanceBefore - 10 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_Success_NormalTransferDoesNotSendTokens() public {
        uint256 bobBalanceBefore = angle.balanceOf(bob);
        uint256 wrapperBalanceBefore = angle.balanceOf(address(wrapper));

        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        // No underlying tokens should have moved
        assertEq(angle.balanceOf(bob), bobBalanceBefore);
        assertEq(angle.balanceOf(address(wrapper)), wrapperBalanceBefore);
        // Bob should not keep wrapper tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_RevertWhen_WrapperHasInsufficientTokens() public {
        // Deplete wrapper's token balance
        uint256 wrapperBalance = angle.balanceOf(address(wrapper));
        vm.prank(alice);
        wrapper.recover(address(angle), alice, wrapperBalance);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }
}

contract Test_PullTokenWrapperTransferImmutable_Integration is PullTokenWrapperTransferImmutableTest {
    function test_Integration_CompleteFlow() public {
        // 1. Holder mints wrapper tokens
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        assertEq(wrapper.balanceOf(alice), 100 ether);
        assertEq(angle.balanceOf(address(wrapper)), 1000 ether); // Underlying already on contract

        // 2. Holder transfers wrapper tokens to distributor
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 80 ether);

        assertEq(wrapper.balanceOf(address(mockDistributor)), 80 ether);
        assertEq(wrapper.balanceOf(alice), 20 ether);

        // 3. Distributor distributes rewards — underlying sent from wrapper contract
        uint256 bobBalanceBefore = angle.balanceOf(bob);

        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 30 ether);

        assertEq(angle.balanceOf(bob), bobBalanceBefore + 30 ether);
        assertEq(angle.balanceOf(address(wrapper)), 1000 ether - 30 ether);
        assertEq(wrapper.balanceOf(bob), 0);

        // 4. Distributor sends fees
        uint256 feeRecipientBalanceBefore = angle.balanceOf(address(mockFeeRecipient));

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(angle.balanceOf(address(mockFeeRecipient)), feeRecipientBalanceBefore + 10 ether);
        assertEq(angle.balanceOf(address(wrapper)), 1000 ether - 30 ether - 10 ether);

        // 5. Check remaining balances
        assertEq(wrapper.balanceOf(address(mockDistributor)), 40 ether); // 80 - 30 - 10
        assertEq(wrapper.balanceOf(alice), 20 ether);
    }

    function test_Integration_HolderCanReclaim() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        uint256 wrapperBalanceBefore = angle.balanceOf(address(wrapper));

        // Distributor sends back to holder — _beforeTokenTransfer fires (from == distributor),
        // so underlying tokens are sent from wrapper to alice
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        assertEq(wrapper.balanceOf(alice), 30 ether);
        assertEq(angle.balanceOf(alice), 30 ether);
        assertEq(angle.balanceOf(address(wrapper)), wrapperBalanceBefore - 30 ether);
    }
}
