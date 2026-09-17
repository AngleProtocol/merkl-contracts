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
/// @dev Every behavioral suite is run twice: once with a holder holding the underlying (e.g. USDC) and once
/// with a holder holding the aToken of the same reserve (e.g. aUSDC), via the `_FromAToken` subclasses that
/// only override `_holderToken`.

contract PullTokenWrapperImmutableAaveDebtTest is Fixture {
    PullTokenWrapperImmutableAaveDebt public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;
    MockAavePool public mockPool;
    MockAaveToken public debtToken;
    MockAaveToken public aToken;
    MockTokenPermit public underlying;

    /// @dev Token held by the holder and pulled during claims: the underlying by default, the aToken in the
    /// `_FromAToken` variants of the suites below
    function _holderToken() internal view virtual returns (MockTokenPermit) {
        return underlying;
    }

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();
        mockPool = new MockAavePool();

        underlying = new MockTokenPermit("Underlying", "UND", 18);
        aToken = new MockAaveToken("aUnderlying", "aUND", 18, address(mockPool), address(underlying));
        debtToken = new MockAaveToken("Variable debt UND", "vUND", 18, address(mockPool), address(underlying));
        mockPool.setDebtToken(address(underlying), address(debtToken));
        mockPool.setAToken(address(underlying), address(aToken));

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new PullTokenWrapperImmutableAaveDebt(address(debtToken), address(_holderToken()), address(creator), alice);

        mockDistributor.setWrapper(address(wrapper));

        // Alice is the holder: she holds the funds used to repay the debt of the claimers
        _holderToken().mint(alice, 1000 ether);
        // Liquidity backing the aTokens on the pool
        underlying.mint(address(mockPool), 10000 ether);

        vm.prank(alice);
        _holderToken().approve(address(wrapper), type(uint256).max);
    }

    /// @dev Gives `borrower` a debt of `amount` on the mock pool
    function _borrow(address borrower, uint256 amount) internal {
        debtToken.mint(borrower, amount);
    }

    /// @dev Balance of the holder in the token it is expected to be pulled from
    function _holderBalance() internal view returns (uint256) {
        return _holderToken().balanceOf(alice);
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_Constructor is PullTokenWrapperImmutableAaveDebtTest {
    function test_Success_AaveDebtSpecificState() public {
        assertEq(wrapper.name(), string(abi.encodePacked(underlying.name(), " (wrapped)")));
        assertEq(wrapper.symbol(), underlying.symbol());
        assertEq(wrapper.pool(), address(mockPool));
        assertEq(wrapper.debtToken(), address(debtToken));
        assertEq(wrapper.underlying(), address(underlying));
        assertEq(wrapper.token(), address(_holderToken()));
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

    function test_RevertWhen_HolderTokenIsAnATokenOfAnotherAsset() public {
        MockTokenPermit otherUnderlying = new MockTokenPermit("Other", "OTH", 18);
        MockAaveToken otherAToken = new MockAaveToken("aOther", "aOTH", 18, address(mockPool), address(otherUnderlying));

        vm.expectRevert(Errors.InvalidParam.selector);
        new PullTokenWrapperImmutableAaveDebt(address(debtToken), address(otherAToken), address(creator), alice);
    }

    function test_RevertWhen_HolderTokenIsAnATokenOfAnotherPool() public {
        MockAavePool otherPool = new MockAavePool();
        MockAaveToken otherAToken = new MockAaveToken("aUnderlying", "aUND", 18, address(otherPool), address(underlying));

        vm.expectRevert(Errors.InvalidParam.selector);
        new PullTokenWrapperImmutableAaveDebt(address(debtToken), address(otherAToken), address(creator), alice);
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_Constructor_FromAToken is Test_PullTokenWrapperImmutableAaveDebt_Constructor {
    function _holderToken() internal view override returns (MockTokenPermit) {
        return aToken;
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_BeforeTokenTransfer is PullTokenWrapperImmutableAaveDebtTest {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(alice);
        wrapper.mint(alice, 500 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 500 ether);
    }

    function test_Success_ClaimLowerThanDebtRepaysWholeClaim() public {
        _borrow(bob, 50 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 30 ether);
        assertEq(_holderBalance(), holderBalanceBefore - 20 ether);
        assertEq(underlying.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_ClaimEqualToDebtRepaysEverything() public {
        _borrow(bob, 20 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(_holderBalance(), holderBalanceBefore - 20 ether);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_ClaimHigherThanDebtOnlyPullsTheDebt() public {
        _borrow(bob, 5 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        // Only the debt is repaid: the unused budget stays with the holder
        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(_holderBalance(), holderBalanceBefore - 5 ether);
        assertEq(underlying.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_NoDebtPullsNothingAndBurnsWrapper() public {
        uint256 holderBalanceBefore = _holderBalance();
        assertEq(debtToken.balanceOf(bob), 0);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(_holderBalance(), holderBalanceBefore);
        assertEq(underlying.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 480 ether);
    }

    function test_Success_NoDebtWorksWithoutHolderAllowance() public {
        vm.prank(alice);
        _holderToken().approve(address(wrapper), 0);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(wrapper.balanceOf(bob), 0);
    }

    /// @dev Fees are paid in kind: the fee recipient has no debt, so capping by its debt would mean no fee
    function test_Success_TransferToFeeRecipientWithoutDebtStillPaysFees() public {
        uint256 holderBalanceBefore = _holderBalance();
        assertEq(debtToken.balanceOf(address(mockFeeRecipient)), 0);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(_holderToken().balanceOf(address(mockFeeRecipient)), 10 ether);
        assertEq(_holderBalance(), holderBalanceBefore - 10 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    /// @dev Fees are taken at campaign creation, where the transfer comes from the campaign creator and not
    /// from the distributor
    function test_Success_TransferToFeeRecipientFromCampaignCreatorPaysFees() public {
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(alice);
        wrapper.mint(bob, 10 ether);
        vm.prank(bob);
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(_holderToken().balanceOf(address(mockFeeRecipient)), 10 ether);
        assertEq(_holderBalance(), holderBalanceBefore - 10 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    /// @dev A fee recipient that happens to have a debt is still paid in kind, its debt is left untouched
    function test_Success_TransferToFeeRecipientDoesNotRepayItsDebt() public {
        _borrow(address(mockFeeRecipient), 4 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(debtToken.balanceOf(address(mockFeeRecipient)), 4 ether);
        assertEq(_holderToken().balanceOf(address(mockFeeRecipient)), 10 ether);
        assertEq(_holderBalance(), holderBalanceBefore - 10 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_Success_NormalTransferDoesNotRepay() public {
        _borrow(bob, 50 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        assertEq(debtToken.balanceOf(bob), 50 ether);
        assertEq(_holderBalance(), holderBalanceBefore);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToHolderPullsNothing() public {
        _borrow(alice, 50 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        assertEq(debtToken.balanceOf(alice), 50 ether);
        assertEq(_holderBalance(), holderBalanceBefore);
        assertEq(wrapper.balanceOf(alice), 30 ether);
    }

    function test_Success_AmountToTransferSentinelOptsOut() public {
        _borrow(bob, 50 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(bob);
        wrapper.setAmountToTransfer(1);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 50 ether);
        assertEq(_holderBalance(), holderBalanceBefore);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_AmountToTransferCapsTheRepayment() public {
        _borrow(bob, 50 ether);
        uint256 holderBalanceBefore = _holderBalance();

        vm.prank(bob);
        wrapper.setAmountToTransfer(5 ether);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 45 ether);
        assertEq(_holderBalance(), holderBalanceBefore - 5 ether);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_RevertWhen_HolderHasInsufficientBalance() public {
        _borrow(bob, 50 ether);
        uint256 holderBalance = _holderBalance();
        vm.prank(alice);
        _holderToken().transfer(address(1), holderBalance);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }

    function test_RevertWhen_HolderHasNotApproved() public {
        _borrow(bob, 50 ether);
        vm.prank(alice);
        _holderToken().approve(address(wrapper), 0);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_BeforeTokenTransfer_FromAToken is Test_PullTokenWrapperImmutableAaveDebt_BeforeTokenTransfer {
    function _holderToken() internal view override returns (MockTokenPermit) {
        return aToken;
    }

    /// @dev The aTokens pulled are withdrawn from the pool before the repayment, so the wrapper never keeps
    /// either the aToken or the underlying
    function test_Success_ClaimLeavesNothingInTheWrapper() public {
        _borrow(bob, 50 ether);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 30 ether);
        assertEq(aToken.balanceOf(address(wrapper)), 0);
        assertEq(underlying.balanceOf(address(wrapper)), 0);
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
        assertEq(_holderBalance(), 1000 ether - 30 ether);
        assertEq(wrapper.balanceOf(bob), 0);

        // Bob claims again but has no debt left: nothing more is pulled from the holder
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 20 ether);

        assertEq(debtToken.balanceOf(bob), 0);
        assertEq(_holderBalance(), 1000 ether - 30 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 30 ether);

        // Fees are paid in kind: the fee recipient is sent 10 and receives 10 of the token held by the holder
        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(_holderToken().balanceOf(address(mockFeeRecipient)), 10 ether);
        assertEq(_holderBalance(), 1000 ether - 40 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 20 ether);
    }

    function test_Integration_HolderCanReclaim() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        uint256 holderBalanceBefore = _holderBalance();

        // Distributor sends back to holder — the holder short-circuit means nothing is pulled nor repaid
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        assertEq(wrapper.balanceOf(alice), 30 ether);
        assertEq(_holderBalance(), holderBalanceBefore);
    }
}

contract Test_PullTokenWrapperImmutableAaveDebt_Integration_FromAToken is Test_PullTokenWrapperImmutableAaveDebt_Integration {
    function _holderToken() internal view override returns (MockTokenPermit) {
        return aToken;
    }
}
