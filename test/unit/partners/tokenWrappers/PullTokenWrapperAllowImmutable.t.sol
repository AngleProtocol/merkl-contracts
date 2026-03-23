// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { PullTokenWrapperAllowImmutable } from "../../../../contracts/partners/tokenWrappers/PullTokenWrapperAllowImmutable.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { IAccessControlManager } from "../../../../contracts/interfaces/IAccessControlManager.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient } from "./TokenWrapperMocks.sol";

contract PullTokenWrapperAllowImmutableTest is Fixture {
    PullTokenWrapperAllowImmutable public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;

    function setUp() public virtual override {
        super.setUp();

        // Deploy mock contracts
        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();

        // Mock the creator to return our mock distributor and fee recipient
        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        // Deploy immutable wrapper directly via constructor
        wrapper = new PullTokenWrapperAllowImmutable(address(angle), address(creator), alice);

        // Set wrapper in mock distributor
        mockDistributor.setWrapper(address(wrapper));

        // Mint tokens to alice (the holder)
        angle.mint(alice, 1000 ether);

        // Approve wrapper to pull tokens from alice
        vm.prank(alice);
        angle.approve(address(wrapper), type(uint256).max);
    }
}

contract Test_PullTokenWrapperAllowImmutable_Constructor is PullTokenWrapperAllowImmutableTest {
    function test_RevertWhen_ZeroAddressHolder() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new PullTokenWrapperAllowImmutable(address(angle), address(creator), address(0));
    }

    function test_RevertWhen_ZeroAddressDistributionCreator() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new PullTokenWrapperAllowImmutable(address(angle), address(0), alice);
    }

    function test_Success() public {
        assertEq(wrapper.name(), string(abi.encodePacked(angle.name(), " (wrapped)")));
        assertEq(wrapper.symbol(), angle.symbol());
        assertEq(wrapper.holder(), alice);
        assertEq(wrapper.token(), address(angle));
        assertEq(address(wrapper.accessControlManager()), address(accessControlManager));
        assertEq(wrapper.distributor(), address(mockDistributor));
        assertEq(wrapper.distributionCreator(), address(creator));
        assertEq(wrapper.decimals(), angle.decimals());
        assertEq(wrapper.feeRecipient(), address(mockFeeRecipient));
    }

    function test_Success_PreAllowedAddresses() public {
        assertEq(wrapper.isAllowed(address(mockDistributor)), 1);
        assertEq(wrapper.isAllowed(alice), 1);
        assertEq(wrapper.isAllowed(address(0)), 1);
        assertEq(wrapper.isAllowed(bob), 0);
    }
}

contract Test_PullTokenWrapperAllowImmutable_Mint is PullTokenWrapperAllowImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.mint(alice, 100 ether);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.mint(alice, 50 ether);

        assertEq(wrapper.balanceOf(alice), 50 ether);
        assertEq(wrapper.totalSupply(), 50 ether);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.mint(alice, 100 ether);

        assertEq(wrapper.balanceOf(alice), 100 ether);
        assertEq(wrapper.totalSupply(), 100 ether);
    }

    function test_Success_MintToRecipientAutoAllows() public {
        assertEq(wrapper.isAllowed(bob), 0);

        vm.prank(alice);
        wrapper.mint(bob, 50 ether);

        assertEq(wrapper.balanceOf(bob), 50 ether);
        assertEq(wrapper.isAllowed(bob), 1);
    }

    function test_Success_MultipleMints() public {
        vm.prank(alice);
        wrapper.mint(alice, 50 ether);

        vm.prank(governor);
        wrapper.mint(alice, 30 ether);

        assertEq(wrapper.balanceOf(alice), 80 ether);
        assertEq(wrapper.totalSupply(), 80 ether);
    }
}

contract Test_PullTokenWrapperAllowImmutable_SetHolder is PullTokenWrapperAllowImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setHolder(charlie);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.setHolder(bob);

        assertEq(wrapper.holder(), bob);
        assertEq(wrapper.isAllowed(alice), 0);
        assertEq(wrapper.isAllowed(bob), 1);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setHolder(charlie);

        assertEq(wrapper.holder(), charlie);
        assertEq(wrapper.isAllowed(alice), 0);
        assertEq(wrapper.isAllowed(charlie), 1);
    }

    function test_Success_NewHolderCanMint() public {
        vm.prank(alice);
        wrapper.setHolder(bob);

        vm.prank(bob);
        wrapper.mint(bob, 25 ether);

        assertEq(wrapper.balanceOf(bob), 25 ether);
    }
}

contract Test_PullTokenWrapperAllowImmutable_ToggleAllowance is PullTokenWrapperAllowImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.toggleAllowance(charlie);
    }

    function test_Success_Holder() public {
        assertEq(wrapper.isAllowed(bob), 0);

        vm.prank(alice);
        wrapper.toggleAllowance(bob);
        assertEq(wrapper.isAllowed(bob), 1);

        vm.prank(alice);
        wrapper.toggleAllowance(bob);
        assertEq(wrapper.isAllowed(bob), 0);
    }

    function test_Success_Governor() public {
        assertEq(wrapper.isAllowed(charlie), 0);

        vm.prank(governor);
        wrapper.toggleAllowance(charlie);
        assertEq(wrapper.isAllowed(charlie), 1);
    }

    function test_Success_AllowedAddressKeepsTokens() public {
        vm.prank(alice);
        wrapper.toggleAllowance(bob);

        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        // Bob is allowed so he keeps the tokens
        assertEq(wrapper.balanceOf(bob), 50 ether);
    }
}

contract Test_PullTokenWrapperAllowImmutable_BeforeTokenTransfer is PullTokenWrapperAllowImmutableTest {
    function setUp() public override {
        super.setUp();

        // Mint wrapper tokens to holder and transfer to distributor
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);
    }

    function test_Success_TransferFromDistributorPullsTokens() public {
        uint256 bobBalanceBefore = angle.balanceOf(bob);
        uint256 aliceBalanceBefore = angle.balanceOf(alice);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        // Bob should receive the underlying tokens (pulled from alice)
        assertEq(angle.balanceOf(bob), bobBalanceBefore + 20 ether);
        // Alice should have tokens deducted
        assertEq(angle.balanceOf(alice), aliceBalanceBefore - 20 ether);
        // Bob should not keep wrapper tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToFeeRecipientPullsTokens() public {
        uint256 feeRecipientBalanceBefore = angle.balanceOf(address(mockFeeRecipient));
        uint256 aliceBalanceBefore = angle.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        // Fee recipient should receive underlying tokens
        assertEq(angle.balanceOf(address(mockFeeRecipient)), feeRecipientBalanceBefore + 10 ether);
        // Alice should have tokens deducted
        assertEq(angle.balanceOf(alice), aliceBalanceBefore - 10 ether);
        // Fee recipient should not keep wrapper tokens
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_Success_NormalTransferDoesNotPullTokens() public {
        uint256 bobAngleBalanceBefore = angle.balanceOf(bob);
        uint256 aliceAngleBalanceBefore = angle.balanceOf(alice);

        // Mint to alice and transfer to bob
        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        // Bob should NOT receive underlying tokens from alice
        assertEq(angle.balanceOf(bob), bobAngleBalanceBefore);
        // Alice's balance should remain unchanged for this transfer
        assertEq(angle.balanceOf(alice), aliceAngleBalanceBefore);
        // Bob should not keep wrapper tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_RevertWhen_HolderHasInsufficientTokens() public {
        // Deplete alice's angle balance
        uint256 aliceAngleBalance = angle.balanceOf(alice);
        vm.prank(alice);
        angle.transfer(address(1), aliceAngleBalance);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }

    function test_RevertWhen_HolderHasNotApproved() public {
        // Remove approval
        vm.prank(alice);
        angle.approve(address(wrapper), 0);

        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 10 ether);
    }
}

contract Test_PullTokenWrapperAllowImmutable_AfterTokenTransfer is PullTokenWrapperAllowImmutableTest {
    function test_Success_BurnsTokensForNonAllowedRecipient() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        uint256 totalSupplyBefore = wrapper.totalSupply();

        // Transfer to bob (not allowed)
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        // Bob should have 0 tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.totalSupply(), totalSupplyBefore - 50 ether);
    }

    function test_Success_KeepsTokensForDistributor() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        uint256 totalSupplyBefore = wrapper.totalSupply();

        // Transfer to distributor (allowed)
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 50 ether);

        assertEq(wrapper.balanceOf(address(mockDistributor)), 50 ether);
        assertEq(wrapper.totalSupply(), totalSupplyBefore);
    }

    function test_Success_KeepsTokensForHolder() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        uint256 totalSupplyBefore = wrapper.totalSupply();

        // Alice transfers to herself (allowed)
        vm.prank(alice);
        wrapper.transfer(alice, 50 ether);

        assertEq(wrapper.balanceOf(alice), 100 ether);
        assertEq(wrapper.totalSupply(), totalSupplyBefore);
    }
}

contract Test_PullTokenWrapperAllowImmutable_SetFeeRecipient is PullTokenWrapperAllowImmutableTest {
    function test_Success() public {
        address newFeeRecipient = vm.addr(999);

        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(newFeeRecipient));

        wrapper.setFeeRecipient();

        assertEq(wrapper.feeRecipient(), newFeeRecipient);
    }

    function test_Success_UpdateAffectsTransfers() public {
        address newFeeRecipient = vm.addr(999);

        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(newFeeRecipient));

        wrapper.setFeeRecipient();

        // Mint and transfer to distributor
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        uint256 newFeeRecipientBalanceBefore = angle.balanceOf(newFeeRecipient);
        uint256 aliceBalanceBefore = angle.balanceOf(alice);

        // Transfer to new fee recipient should pull tokens
        vm.prank(address(mockDistributor));
        wrapper.transfer(newFeeRecipient, 10 ether);

        assertEq(angle.balanceOf(newFeeRecipient), newFeeRecipientBalanceBefore + 10 ether);
        assertEq(angle.balanceOf(alice), aliceBalanceBefore - 10 ether);
    }
}

contract Test_PullTokenWrapperAllowImmutable_Decimals is PullTokenWrapperAllowImmutableTest {
    function test_Success_MatchesUnderlyingToken() public {
        assertEq(wrapper.decimals(), angle.decimals());
    }
}

contract Test_PullTokenWrapperAllowImmutable_Integration is PullTokenWrapperAllowImmutableTest {
    function test_Integration_CompleteFlow() public {
        // 1. Holder mints wrapper tokens
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        assertEq(wrapper.balanceOf(alice), 100 ether);
        assertEq(angle.balanceOf(alice), 1000 ether); // No underlying tokens moved yet

        // 2. Holder creates a campaign by transferring wrapper tokens to distributor
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 80 ether);

        assertEq(wrapper.balanceOf(address(mockDistributor)), 80 ether);
        assertEq(wrapper.balanceOf(alice), 20 ether);
        assertEq(angle.balanceOf(alice), 1000 ether); // Still no underlying tokens moved

        // 3. Distributor distributes rewards to bob
        uint256 bobAngleBalanceBefore = angle.balanceOf(bob);

        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 30 ether);

        // Bob receives underlying ANGLE tokens (pulled from alice)
        assertEq(angle.balanceOf(bob), bobAngleBalanceBefore + 30 ether);
        assertEq(angle.balanceOf(alice), 1000 ether - 30 ether);
        // Bob doesn't keep wrapper tokens (burned)
        assertEq(wrapper.balanceOf(bob), 0);

        // 4. Distributor sends fees
        uint256 feeRecipientAngleBalanceBefore = angle.balanceOf(address(mockFeeRecipient));

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        // Fee recipient receives underlying ANGLE tokens
        assertEq(angle.balanceOf(address(mockFeeRecipient)), feeRecipientAngleBalanceBefore + 10 ether);
        assertEq(angle.balanceOf(alice), 1000 ether - 30 ether - 10 ether);

        // 5. Check remaining balances
        assertEq(wrapper.balanceOf(address(mockDistributor)), 40 ether); // 80 - 30 - 10
        assertEq(wrapper.balanceOf(alice), 20 ether);
    }

    function test_Integration_MultipleHolders() public {
        // Setup: Transfer some ANGLE to bob and have him approve
        angle.mint(bob, 500 ether);
        vm.prank(bob);
        angle.approve(address(wrapper), type(uint256).max);

        // 1. Alice mints and campaigns
        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 50 ether);

        // 2. Change holder to bob
        vm.prank(alice);
        wrapper.setHolder(bob);

        // 3. Bob mints additional wrapper tokens
        vm.prank(bob);
        wrapper.mint(bob, 50 ether);
        vm.prank(bob);
        wrapper.transfer(address(mockDistributor), 50 ether);

        assertEq(wrapper.balanceOf(address(mockDistributor)), 100 ether);

        // 4. Distributor sends rewards - should pull from bob (current holder)
        uint256 charlieAngleBalanceBefore = angle.balanceOf(charlie);
        uint256 bobAngleBalanceBefore = angle.balanceOf(bob);
        uint256 aliceAngleBalanceBefore = angle.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(charlie, 60 ether);

        // Charlie receives tokens pulled from bob (current holder), not alice
        assertEq(angle.balanceOf(charlie), charlieAngleBalanceBefore + 60 ether);
        assertEq(angle.balanceOf(bob), bobAngleBalanceBefore - 60 ether);
        assertEq(angle.balanceOf(alice), aliceAngleBalanceBefore); // Unchanged
    }

    function test_Integration_HolderCanReclaim() public {
        // 1. Mint and send to distributor
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        // 2. Distributor sends some back to holder
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        // Alice should keep the wrapper tokens since she's the holder (allowed)
        assertEq(wrapper.balanceOf(alice), 30 ether);

        // No underlying tokens should have moved (holder receives from distributor)
        assertEq(angle.balanceOf(alice), 1000 ether);
    }
}

contract Test_PullTokenWrapperAllowImmutable_Recover is PullTokenWrapperAllowImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.recover(address(angle), bob, 1 ether);
    }

    function test_Success_Holder() public {
        // Send some tokens to the wrapper
        angle.mint(address(wrapper), 100 ether);

        uint256 bobBalanceBefore = angle.balanceOf(bob);

        vm.prank(alice);
        wrapper.recover(address(angle), bob, 50 ether);

        assertEq(angle.balanceOf(bob), bobBalanceBefore + 50 ether);
    }

    function test_Success_Governor() public {
        angle.mint(address(wrapper), 100 ether);

        uint256 charlieBalanceBefore = angle.balanceOf(charlie);

        vm.prank(governor);
        wrapper.recover(address(angle), charlie, 100 ether);

        assertEq(angle.balanceOf(charlie), charlieBalanceBefore + 100 ether);
    }

    function test_Success_RecoverDifferentToken() public {
        agEUR.mint(address(wrapper), 200 ether);

        uint256 bobBalanceBefore = agEUR.balanceOf(bob);

        vm.prank(alice);
        wrapper.recover(address(agEUR), bob, 200 ether);

        assertEq(agEUR.balanceOf(bob), bobBalanceBefore + 200 ether);
    }
}

contract Test_PullTokenWrapperAllowImmutable_EdgeCases is PullTokenWrapperAllowImmutableTest {
    function test_EdgeCase_TransferZeroAmount() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(bob, 0);

        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(alice), 100 ether);
    }

    function test_EdgeCase_MintZeroAmount() public {
        vm.prank(alice);
        wrapper.mint(alice, 0);

        assertEq(wrapper.balanceOf(alice), 0);
        assertEq(wrapper.totalSupply(), 0);
    }

    function test_EdgeCase_SetHolderToSameAddress() public {
        vm.prank(alice);
        wrapper.setHolder(alice);

        assertEq(wrapper.holder(), alice);
        // Alice should still be allowed (set to 0 then back to 1)
        assertEq(wrapper.isAllowed(alice), 1);
    }

    function test_Success_TransferBetweenDistributorAndHolder() public {
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        // Transfer from holder to distributor
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 50 ether);

        assertEq(wrapper.balanceOf(address(mockDistributor)), 50 ether);
        assertEq(wrapper.balanceOf(alice), 50 ether);

        // Transfer back from distributor to holder
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 20 ether);

        assertEq(wrapper.balanceOf(alice), 70 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 30 ether);
    }
}
