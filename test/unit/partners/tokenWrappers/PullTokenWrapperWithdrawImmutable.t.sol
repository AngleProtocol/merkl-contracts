// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { PullTokenWrapperWithdrawImmutable } from "../../../../contracts/partners/tokenWrappers/PullTokenWrapperWithdrawImmutable.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient, MockAaveToken, MockAavePool } from "./TokenWrapperMocks.sol";
import { MockTokenPermit } from "../../../../contracts/mock/MockTokenPermit.sol";

/// @dev Base contract tests (mint, setHolder, toggleAllowance, afterTokenTransfer, setFeeRecipient,
/// decimals, edge cases) are covered via PullTokenWrapperAllowImmutable.t.sol since they test
/// shared logic in PullTokenWrapperImmutableBase. This file only tests Withdraw-specific behavior.

contract PullTokenWrapperWithdrawImmutableTest is Fixture {
    PullTokenWrapperWithdrawImmutable public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;
    MockAavePool public mockPool;
    MockAaveToken public aToken;
    MockTokenPermit public underlying;

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();
        mockPool = new MockAavePool();

        underlying = new MockTokenPermit("Underlying", "UND", 18);
        aToken = new MockAaveToken("aUnderlying", "aUND", 18, address(mockPool), address(underlying));

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new PullTokenWrapperWithdrawImmutable(address(aToken), address(creator), alice);

        mockDistributor.setWrapper(address(wrapper));

        aToken.mint(alice, 1000 ether);
        underlying.mint(address(mockPool), 10000 ether);

        vm.prank(alice);
        aToken.approve(address(wrapper), type(uint256).max);
    }
}

contract Test_PullTokenWrapperWithdrawImmutable_Constructor is PullTokenWrapperWithdrawImmutableTest {
    function test_Success_WithdrawSpecificState() public {
        assertEq(wrapper.name(), string(abi.encodePacked(underlying.name(), " (wrapped)")));
        assertEq(wrapper.symbol(), underlying.symbol());
        assertEq(wrapper.pool(), address(mockPool));
        assertEq(wrapper.underlying(), address(underlying));
        assertEq(wrapper.token(), address(aToken));
    }
}

contract Test_PullTokenWrapperWithdrawImmutable_BeforeTokenTransfer is PullTokenWrapperWithdrawImmutableTest {
    function setUp() public override {
        super.setUp();

        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);
    }

    function test_Success_TransferFromDistributorWithdrawsAndSends() public {
        uint256 bobUnderlyingBefore = underlying.balanceOf(bob);
        uint256 aliceATokenBefore = aToken.balanceOf(alice);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(underlying.balanceOf(bob), bobUnderlyingBefore + 20 ether);
        assertEq(aToken.balanceOf(alice), aliceATokenBefore - 20 ether);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToFeeRecipientWithdrawsAndSends() public {
        uint256 feeRecipientUnderlyingBefore = underlying.balanceOf(address(mockFeeRecipient));
        uint256 aliceATokenBefore = aToken.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(underlying.balanceOf(address(mockFeeRecipient)), feeRecipientUnderlyingBefore + 10 ether);
        assertEq(aToken.balanceOf(alice), aliceATokenBefore - 10 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_Success_NormalTransferDoesNotWithdraw() public {
        uint256 bobUnderlyingBefore = underlying.balanceOf(bob);
        uint256 aliceATokenBefore = aToken.balanceOf(alice);

        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        assertEq(underlying.balanceOf(bob), bobUnderlyingBefore);
        assertEq(aToken.balanceOf(alice), aliceATokenBefore);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_RevertWhen_HolderHasInsufficientATokens() public {
        uint256 aliceATokenBalance = aToken.balanceOf(alice);
        vm.prank(alice);
        aToken.transfer(address(1), aliceATokenBalance);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }

    function test_RevertWhen_HolderHasNotApproved() public {
        vm.prank(alice);
        aToken.approve(address(wrapper), 0);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }
}

contract Test_PullTokenWrapperWithdrawImmutable_Integration is PullTokenWrapperWithdrawImmutableTest {
    function test_Integration_CompleteFlow() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 80 ether);

        // Distributor distributes rewards — bob receives underlying via Aave withdraw
        uint256 bobUnderlyingBefore = underlying.balanceOf(bob);

        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 30 ether);

        assertEq(underlying.balanceOf(bob), bobUnderlyingBefore + 30 ether);
        assertEq(aToken.balanceOf(alice), 1000 ether - 30 ether);
        assertEq(wrapper.balanceOf(bob), 0);

        // Distributor sends fees
        uint256 feeRecipientUnderlyingBefore = underlying.balanceOf(address(mockFeeRecipient));

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(underlying.balanceOf(address(mockFeeRecipient)), feeRecipientUnderlyingBefore + 10 ether);
        assertEq(aToken.balanceOf(alice), 1000 ether - 30 ether - 10 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 40 ether);
    }

    function test_Integration_HolderCanReclaim() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        uint256 aliceATokenBefore = aToken.balanceOf(alice);

        // Distributor sends back to holder — _beforeTokenTransfer fires (from == distributor),
        // so aTokens are pulled from alice and withdrawn to underlying
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        assertEq(wrapper.balanceOf(alice), 30 ether);
        assertEq(aToken.balanceOf(alice), aliceATokenBefore - 30 ether);
        assertEq(underlying.balanceOf(alice), 30 ether);
    }
}
