// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { PullTokenWrapperVaultImmutable } from "../../../../contracts/partners/tokenWrappers/PullTokenWrapperVaultImmutable.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient } from "./TokenWrapperMocks.sol";
import { ERC4626, ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @dev Simple ERC4626 vault for testing
contract MockVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Mock Vault", "mVAULT") ERC4626(asset_) {}
}

/// @dev Base contract tests (mint, setHolder, toggleAllowance, afterTokenTransfer, setFeeRecipient,
/// decimals, edge cases) are covered via PullTokenWrapperAllowImmutable.t.sol since they test
/// shared logic in PullTokenWrapperImmutableBase. This file only tests Vault-specific behavior.

contract PullTokenWrapperVaultImmutableTest is Fixture {
    PullTokenWrapperVaultImmutable public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;
    MockVault public vault;

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();
        vault = new MockVault(IERC20(address(angle)));

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new PullTokenWrapperVaultImmutable(address(angle), address(creator), alice, address(vault));

        mockDistributor.setWrapper(address(wrapper));

        angle.mint(alice, 1000 ether);

        vm.prank(alice);
        angle.approve(address(wrapper), type(uint256).max);
    }
}

contract Test_PullTokenWrapperVaultImmutable_Constructor is PullTokenWrapperVaultImmutableTest {
    function test_RevertWhen_ZeroAddressVault() public {
        vm.expectRevert();
        new PullTokenWrapperVaultImmutable(address(angle), address(creator), alice, address(0));
    }

    function test_Success_VaultSpecificState() public {
        assertEq(wrapper.vault(), address(vault));
        assertEq(angle.allowance(address(wrapper), address(vault)), type(uint256).max);
    }
}

contract Test_PullTokenWrapperVaultImmutable_BeforeTokenTransfer is PullTokenWrapperVaultImmutableTest {
    function setUp() public override {
        super.setUp();

        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);
    }

    function test_Success_TransferFromDistributorDepositsIntoVault() public {
        uint256 aliceAngleBefore = angle.balanceOf(alice);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        assertEq(vault.balanceOf(bob), 20 ether);
        assertEq(angle.balanceOf(alice), aliceAngleBefore - 20 ether);
        assertEq(angle.balanceOf(address(vault)), 20 ether);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToFeeRecipientDepositsIntoVault() public {
        uint256 aliceAngleBefore = angle.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(vault.balanceOf(address(mockFeeRecipient)), 10 ether);
        assertEq(angle.balanceOf(alice), aliceAngleBefore - 10 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_Success_NormalTransferDoesNotDeposit() public {
        uint256 aliceAngleBefore = angle.balanceOf(alice);

        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        assertEq(vault.balanceOf(bob), 0);
        assertEq(angle.balanceOf(alice), aliceAngleBefore);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_RevertWhen_HolderHasInsufficientTokens() public {
        uint256 aliceAngleBalance = angle.balanceOf(alice);
        vm.prank(alice);
        angle.transfer(address(1), aliceAngleBalance);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }

    function test_RevertWhen_HolderHasNotApproved() public {
        vm.prank(alice);
        angle.approve(address(wrapper), 0);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }
}

contract Test_PullTokenWrapperVaultImmutable_SetVaultAllowance is PullTokenWrapperVaultImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setVaultAllowance(100 ether);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.setVaultAllowance(500 ether);

        assertEq(angle.allowance(address(wrapper), address(vault)), 500 ether);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setVaultAllowance(1000 ether);

        assertEq(angle.allowance(address(wrapper), address(vault)), 1000 ether);
    }

    function test_Success_ResetToMax() public {
        vm.prank(alice);
        wrapper.setVaultAllowance(100 ether);
        assertEq(angle.allowance(address(wrapper), address(vault)), 100 ether);

        vm.prank(alice);
        wrapper.setVaultAllowance(type(uint256).max);
        assertEq(angle.allowance(address(wrapper), address(vault)), type(uint256).max);
    }
}

contract Test_PullTokenWrapperVaultImmutable_Integration is PullTokenWrapperVaultImmutableTest {
    function test_Integration_CompleteFlow() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 80 ether);

        // Distributor distributes rewards — bob receives vault shares
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 30 ether);

        assertEq(vault.balanceOf(bob), 30 ether);
        assertEq(angle.balanceOf(alice), 1000 ether - 30 ether);
        assertEq(angle.balanceOf(address(vault)), 30 ether);
        assertEq(wrapper.balanceOf(bob), 0);

        // Distributor sends fees — also deposited into vault
        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(vault.balanceOf(address(mockFeeRecipient)), 10 ether);
        assertEq(angle.balanceOf(alice), 1000 ether - 30 ether - 10 ether);
        assertEq(angle.balanceOf(address(vault)), 40 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 40 ether);
    }

    function test_Integration_HolderCanReclaim() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        uint256 aliceAngleBefore = angle.balanceOf(alice);

        // Distributor sends back to holder — _beforeTokenTransfer fires (from == distributor),
        // so tokens are pulled from alice and deposited into the vault for alice
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        assertEq(wrapper.balanceOf(alice), 30 ether);
        assertEq(angle.balanceOf(alice), aliceAngleBefore - 30 ether);
        assertEq(vault.balanceOf(alice), 30 ether);
    }
}
