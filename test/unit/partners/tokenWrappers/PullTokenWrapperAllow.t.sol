// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { PullTokenWrapperAllow } from "../../../../contracts/partners/tokenWrappers/PullTokenWrapperAllow.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { IAccessControlManager } from "../../../../contracts/interfaces/IAccessControlManager.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Mock contract to simulate the Distributor
contract MockDistributor {
    PullTokenWrapperAllow public wrapper;

    function setWrapper(address _wrapper) external {
        wrapper = PullTokenWrapperAllow(_wrapper);
    }

    /// @dev Simulates a transfer from distributor (e.g., during claim)
    function simulateClaim(address to, uint256 amount) external {
        wrapper.transfer(to, amount);
    }
}

/// @dev Mock contract to simulate fee recipient
contract MockFeeRecipient {
    // Empty contract for fee recipient
}

contract PullTokenWrapperAllowTest is Fixture {
    PullTokenWrapperAllow public wrapper;
    PullTokenWrapperAllow public wrapperImpl;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;

    function setUp() public virtual override {
        super.setUp();

        // Deploy mock contracts
        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();

        // Deploy PullTokenWrapperAllow implementation
        wrapperImpl = new PullTokenWrapperAllow();
        wrapper = PullTokenWrapperAllow(deployUUPS(address(wrapperImpl), hex""));

        // Mock the creator to return our mock distributor and fee recipient
        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        // Initialize the wrapper with angle token and alice as holder
        wrapper.initialize(address(angle), address(creator), alice, "Wrapped ANGLE", "wANGLE");

        // Set wrapper in mock distributor
        mockDistributor.setWrapper(address(wrapper));

        // Mint tokens to alice (the holder)
        angle.mint(alice, 1000 ether);

        // Approve wrapper to pull tokens from alice
        vm.prank(alice);
        angle.approve(address(wrapper), type(uint256).max);
    }
}

contract Test_PullTokenWrapperAllow_Initialize is PullTokenWrapperAllowTest {
    PullTokenWrapperAllow w;

    function setUp() public override {
        super.setUp();
        w = PullTokenWrapperAllow(deployUUPS(address(new PullTokenWrapperAllow()), hex""));
    }

    function test_RevertWhen_CalledOnImplem() public {
        vm.expectRevert("Initializable: contract is already initialized");
        wrapperImpl.initialize(address(0), address(0), address(0), "", "");
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        w.initialize(address(angle), address(creator), address(0), "Test", "TEST");
    }

    function test_Success() public {
        w.initialize(address(angle), address(creator), alice, "Test Token", "TEST");

        assertEq(w.name(), "Test Token");
        assertEq(w.symbol(), "TEST");
        assertEq(w.holder(), alice);
        assertEq(w.token(), address(angle));
        assertEq(address(w.accessControlManager()), address(accessControlManager));
        assertEq(w.distributor(), address(mockDistributor));
        assertEq(w.distributionCreator(), address(creator));
        assertEq(w.decimals(), angle.decimals());
        assertEq(w.feeRecipient(), address(mockFeeRecipient));
    }
}

contract Test_PullTokenWrapperAllow_Mint is PullTokenWrapperAllowTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.mint(100 ether);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.mint(50 ether);

        assertEq(wrapper.balanceOf(alice), 50 ether);
        assertEq(wrapper.totalSupply(), 50 ether);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.mint(100 ether);

        assertEq(wrapper.balanceOf(alice), 100 ether);
        assertEq(wrapper.totalSupply(), 100 ether);
    }

    function test_Success_MultipleMints() public {
        vm.prank(alice);
        wrapper.mint(50 ether);

        vm.prank(governor);
        wrapper.mint(30 ether);

        assertEq(wrapper.balanceOf(alice), 80 ether);
        assertEq(wrapper.totalSupply(), 80 ether);
    }
}

contract Test_PullTokenWrapperAllow_SetHolder is PullTokenWrapperAllowTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setHolder(charlie);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.setHolder(bob);

        assertEq(wrapper.holder(), bob);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setHolder(charlie);

        assertEq(wrapper.holder(), charlie);
    }

    function test_Success_NewHolderCanMint() public {
        // Change holder to bob
        vm.prank(alice);
        wrapper.setHolder(bob);

        // Bob should now be able to mint
        vm.prank(bob);
        wrapper.mint(25 ether);

        assertEq(wrapper.balanceOf(bob), 25 ether);
    }
}

contract Test_PullTokenWrapperAllow_BeforeTokenTransfer is PullTokenWrapperAllowTest {
    function setUp() public override {
        super.setUp();

        // Mint wrapper tokens to holder and transfer to distributor
        vm.prank(alice);
        wrapper.mint(100 ether);

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

        // Mint to bob
        vm.prank(alice);
        wrapper.mint(50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        // Charlie should NOT receive underlying tokens from alice
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

contract Test_PullTokenWrapperAllow_AfterTokenTransfer is PullTokenWrapperAllowTest {
    function test_Success_BurnsTokensForNonAllowedRecipient() public {
        // Mint to alice
        vm.prank(alice);
        wrapper.mint(100 ether);

        uint256 totalSupplyBefore = wrapper.totalSupply();

        // Transfer to bob (not distributor, holder, or zero address)
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        // Bob should have 0 tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.totalSupply(), totalSupplyBefore - 50 ether);
    }

    function test_Success_KeepsTokensForDistributor() public {
        // Mint to alice
        vm.prank(alice);
        wrapper.mint(100 ether);

        uint256 totalSupplyBefore = wrapper.totalSupply();

        // Transfer to distributor
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 50 ether);

        // Distributor should keep the tokens
        assertEq(wrapper.balanceOf(address(mockDistributor)), 50 ether);
        assertEq(wrapper.totalSupply(), totalSupplyBefore);
    }

    function test_Success_KeepsTokensForHolder() public {
        // Mint to alice
        vm.prank(alice);
        wrapper.mint(100 ether);

        uint256 totalSupplyBefore = wrapper.totalSupply();

        // Alice transfers to herself
        vm.prank(alice);
        wrapper.transfer(alice, 50 ether);

        // Alice should keep the tokens
        assertEq(wrapper.balanceOf(alice), 100 ether);
        assertEq(wrapper.totalSupply(), totalSupplyBefore);
    }
}

contract Test_PullTokenWrapperAllow_SetFeeRecipient is PullTokenWrapperAllowTest {
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
        wrapper.mint(100 ether);
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

contract Test_PullTokenWrapperAllow_Decimals is PullTokenWrapperAllowTest {
    function test_Success_MatchesUnderlyingToken() public {
        assertEq(wrapper.decimals(), angle.decimals());
    }
}

contract Test_PullTokenWrapperAllow_Integration is PullTokenWrapperAllowTest {
    function test_Integration_CompleteFlow() public {
        // 1. Holder mints wrapper tokens
        vm.prank(alice);
        wrapper.mint(100 ether);

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
        wrapper.mint(50 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 50 ether);

        // 2. Change holder to bob
        vm.prank(alice);
        wrapper.setHolder(bob);

        // 3. Bob mints additional wrapper tokens
        vm.prank(bob);
        wrapper.mint(50 ether);
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
        wrapper.mint(100 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);

        // 2. Distributor sends some back to holder
        vm.prank(address(mockDistributor));
        wrapper.transfer(alice, 30 ether);

        // Alice should keep the wrapper tokens since she's the holder
        assertEq(wrapper.balanceOf(alice), 30 ether);

        // No underlying tokens should have moved (holder receives from distributor)
        assertEq(angle.balanceOf(alice), 1000 ether);
    }
}

contract Test_PullTokenWrapperAllow_EdgeCases is PullTokenWrapperAllowTest {
    function test_EdgeCase_TransferZeroAmount() public {
        vm.prank(alice);
        wrapper.mint(100 ether);

        vm.prank(alice);
        wrapper.transfer(bob, 0);

        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.balanceOf(alice), 100 ether);
    }

    function test_EdgeCase_MintZeroAmount() public {
        vm.prank(alice);
        wrapper.mint(0);

        assertEq(wrapper.balanceOf(alice), 0);
        assertEq(wrapper.totalSupply(), 0);
    }

    function test_EdgeCase_SetHolderToSameAddress() public {
        vm.prank(alice);
        wrapper.setHolder(alice);

        assertEq(wrapper.holder(), alice);
    }

    function test_Success_TransferBetweenDistributorAndHolder() public {
        // Mint to holder
        vm.prank(alice);
        wrapper.mint(100 ether);

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
