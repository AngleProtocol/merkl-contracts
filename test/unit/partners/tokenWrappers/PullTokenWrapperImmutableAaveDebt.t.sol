// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { PullTokenWrapperImmutableAaveDebt } from "../../../../contracts/partners/tokenWrappers/PullTokenWrapperImmutableAaveDebt.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient, MockAaveToken, MockAavePool } from "./TokenWrapperMocks.sol";
import { MockTokenPermit } from "../../../../contracts/mock/MockTokenPermit.sol";

/// @dev Base contract tests (mint, setHolder, toggleAllowance, afterTokenTransfer, setFeeRecipient,
/// decimals, edge cases) are covered via PullTokenWrapperAllowImmutable.t.sol since they test
/// shared logic in PullTokenWrapperImmutableBase. This file only tests AaveDebt-specific behavior.

contract PullTokenWrapperImmutableAaveDebtTest is Fixture {
    PullTokenWrapperImmutableAaveDebt public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;
    MockAavePool public mockPool;
    MockAaveToken public debtToken;
    MockTokenPermit public underlying;

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();
        mockPool = new MockAavePool();

        underlying = new MockTokenPermit("Underlying", "UND", 18);
        debtToken = new MockAaveToken("Variable debt UND", "vUND", 18, address(mockPool), address(underlying));
        mockPool.setDebtToken(address(underlying), address(debtToken));

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new PullTokenWrapperImmutableAaveDebt(address(debtToken), address(creator), alice);

        mockDistributor.setWrapper(address(wrapper));

        // Alice is the holder: she holds the underlying that is used to repay the debt of the claimers
        underlying.mint(alice, 1000 ether);

        vm.prank(alice);
        underlying.approve(address(wrapper), type(uint256).max);
    }

    /// @dev Gives `borrower` a debt of `amount` on the mock pool
    function _borrow(address borrower, uint256 amount) internal {
        debtToken.mint(borrower, amount);
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_Constructor is PullTokenWrapperImmutableAaveDebtTest {
    function test_Success_AaveDebtSpecificState() public {
        assertEq(wrapper.name(), string(abi.encodePacked(underlying.name(), " (wrapped)")));
        assertEq(wrapper.symbol(), underlying.symbol());
        assertEq(wrapper.pool(), address(mockPool));
        assertEq(wrapper.debtToken(), address(debtToken));
        assertEq(wrapper.token(), address(underlying));
        assertEq(wrapper.decimals(), underlying.decimals());
        assertEq(wrapper.INTEREST_RATE_MODE(), 2);
        assertEq(underlying.allowance(address(wrapper), address(mockPool)), type(uint256).max);
    }

    function test_Success_ApprovePool() public {
        vm.prank(address(wrapper));
        underlying.approve(address(mockPool), 0);
        assertEq(underlying.allowance(address(wrapper), address(mockPool)), 0);

        wrapper.approvePool();
        assertEq(underlying.allowance(address(wrapper), address(mockPool)), type(uint256).max);
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_BeforeTokenTransfer is PullTokenWrapperImmutableAaveDebtTest {
    function setUp() public override {
        super.setUp();

        vm.prank(alice);
        wrapper.mint(alice, 500 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 500 ether);
    }

    function test_Success_ClaimLowerThanDebtRepaysWholeClaim() public {
        _borrow(bob, 50 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 30 ether);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore - 20 ether);
        assertEq(underlying.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_ClaimEqualToDebtRepaysEverything() public {
        _borrow(bob, 20 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore - 20 ether);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_ClaimHigherThanDebtOnlyPullsTheDebt() public {
        _borrow(bob, 5 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        // Only the debt is repaid: the unused budget stays with the holder
        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore - 5 ether);
        assertEq(underlying.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_NoDebtPullsNothingAndBurnsWrapper() public {
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);
        assertEq(debtToken.balanceOf(bob), 0);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(underlying.balanceOf(alice), aliceBalanceBefore);
        assertEq(underlying.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 480 ether);
    }

    function test_Success_NoDebtWorksWithoutHolderAllowance() public {
        vm.prank(alice);
        underlying.approve(address(wrapper), 0);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToFeeRecipientRepaysItsDebt() public {
        _borrow(address(mockFeeRecipient), 4 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(debtToken.balanceOf(address(mockFeeRecipient)), 0);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore - 4 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_Success_TransferToFeeRecipientWithoutDebtPullsNothing() public {
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(underlying.balanceOf(alice), aliceBalanceBefore);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_Success_NormalTransferDoesNotRepay() public {
        _borrow(bob, 50 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        assertEq(debtToken.balanceOf(bob), 50 ether);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToHolderPullsNothing() public {
        _borrow(alice, 50 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        assertEq(debtToken.balanceOf(alice), 50 ether);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore);
        assertEq(wrapper.balanceOf(alice), 30 ether);
    }

    function test_Success_AmountToTransferSentinelOptsOut() public {
        _borrow(bob, 50 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(bob);
        wrapper.setAmountToTransfer(1);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 50 ether);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_AmountToTransferCapsTheRepayment() public {
        _borrow(bob, 50 ether);
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(bob);
        wrapper.setAmountToTransfer(5 ether);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 45 ether);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore - 5 ether);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_RevertWhen_HolderHasInsufficientUnderlying() public {
        _borrow(bob, 50 ether);
        uint256 aliceBalance = underlying.balanceOf(alice);
        vm.prank(alice);
        underlying.transfer(address(1), aliceBalance);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }

    function test_RevertWhen_HolderHasNotApproved() public {
        _borrow(bob, 50 ether);
        vm.prank(alice);
        underlying.approve(address(wrapper), 0);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_Integration is PullTokenWrapperImmutableAaveDebtTest {
    function test_Integration_CompleteFlow() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 80 ether);

        // Bob borrowed 30, claims 30: his whole debt is repaid from the holder's balance
        _borrow(bob, 30 ether);

        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 30 ether);

        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(underlying.balanceOf(alice), 1000 ether - 30 ether);
        assertEq(wrapper.balanceOf(bob), 0);

        // Bob claims again but has no debt left: nothing more is pulled from the holder
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(underlying.balanceOf(alice), 1000 ether - 30 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 30 ether);

        // The fee recipient has a 5 debt and is sent 10: only 5 are pulled
        _borrow(address(mockFeeRecipient), 5 ether);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(debtToken.balanceOf(address(mockFeeRecipient)), 0);
        assertEq(underlying.balanceOf(alice), 1000 ether - 35 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 20 ether);
    }

    function test_Integration_HolderCanReclaim() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        // Distributor sends back to holder — the holder short-circuit means nothing is pulled nor repaid
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        assertEq(wrapper.balanceOf(alice), 30 ether);
        assertEq(underlying.balanceOf(alice), aliceBalanceBefore);
    }
}
