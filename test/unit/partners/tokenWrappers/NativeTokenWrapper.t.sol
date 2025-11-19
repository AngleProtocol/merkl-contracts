// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { NativeTokenWrapper } from "../../../../contracts/partners/tokenWrappers/NativeTokenWrapper.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { IAccessControlManager } from "../../../../contracts/interfaces/IAccessControlManager.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";

/// @dev Mock contract to simulate the Distributor
contract MockDistributor {
    NativeTokenWrapper public wrapper;

    function setWrapper(address _wrapper) external {
        wrapper = NativeTokenWrapper(payable(_wrapper));
    }

    /// @dev Simulates a transfer from distributor (e.g., during claim)
    function simulateClaim(address to, uint256 amount) external {
        wrapper.transfer(to, amount);
    }

    /// @dev Allow receiving ETH
    receive() external payable {}
}

/// @dev Mock contract to simulate fee recipient
contract MockFeeRecipient {
    /// @dev Allow receiving ETH
    receive() external payable {}
}

/// @dev Mock contract that cannot receive ETH (no receive/fallback)
contract MockNonPayable {
    // Intentionally no receive or fallback function
}

contract NativeTokenWrapperTest is Fixture {
    NativeTokenWrapper public wrapper;
    NativeTokenWrapper public wrapperImpl;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;

    function setUp() public virtual override {
        super.setUp();

        // Deploy mock contracts
        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();

        // Deploy NativeTokenWrapper implementation
        wrapperImpl = new NativeTokenWrapper();
        wrapper = NativeTokenWrapper(payable(deployUUPS(address(wrapperImpl), hex"")));

        // Mock the creator to return our mock distributor and fee recipient
        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        // Initialize the wrapper
        wrapper.initialize(address(creator), alice, "Wrapped Native Token", "WNATIVE");

        // Set wrapper in mock distributor
        mockDistributor.setWrapper(address(wrapper));

        // Fund the wrapper with ETH for testing
        vm.deal(address(wrapper), 100 ether);
    }
}

contract Test_NativeTokenWrapper_Initialize is NativeTokenWrapperTest {
    NativeTokenWrapper w;

    function setUp() public override {
        super.setUp();
        w = NativeTokenWrapper(payable(deployUUPS(address(new NativeTokenWrapper()), hex"")));
    }

    function test_RevertWhen_CalledOnImplem() public {
        vm.expectRevert("Initializable: contract is already initialized");
        wrapperImpl.initialize(address(0), address(0), "", "");
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        w.initialize(address(creator), address(0), "Test", "TEST");
    }

    function test_Success() public {
        w.initialize(address(creator), alice, "Test Token", "TEST");

        assertEq(w.name(), "Test Token");
        assertEq(w.symbol(), "TEST");
        assertEq(w.minter(), alice);
        assertEq(address(w.accessControlManager()), address(accessControlManager));
        assertEq(w.distributor(), address(mockDistributor));
        assertEq(w.distributionCreator(), address(creator));
        assertEq(w.decimals(), 18);

        // Check allowed addresses
        assertEq(w.isAllowed(address(mockDistributor)), 1);
        assertEq(w.isAllowed(alice), 1);
        assertEq(w.isAllowed(address(0)), 1);
    }
}

contract Test_NativeTokenWrapper_Receive is NativeTokenWrapperTest {
    function test_Success_ReceiveETH() public {
        uint256 balanceBefore = address(wrapper).balance;

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        (bool success, ) = address(wrapper).call{ value: 5 ether }("");

        assertTrue(success);
        assertEq(address(wrapper).balance, balanceBefore + 5 ether);
    }

    function test_Success_FallbackReceiveETH() public {
        uint256 balanceBefore = address(wrapper).balance;

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        (bool success, ) = address(wrapper).call{ value: 3 ether }("0x1234");

        assertTrue(success);
        assertEq(address(wrapper).balance, balanceBefore + 3 ether);
    }
}

contract Test_NativeTokenWrapper_Mint is NativeTokenWrapperTest {
    function test_RevertWhen_NotMinterOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.mint(charlie, 1 ether);
    }

    function test_Success_Minter() public {
        vm.prank(alice);
        wrapper.mint(bob, 5 ether);

        assertEq(wrapper.balanceOf(bob), 5 ether);
        assertEq(wrapper.isAllowed(bob), 1);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.mint(charlie, 10 ether);

        assertEq(wrapper.balanceOf(charlie), 10 ether);
        assertEq(wrapper.isAllowed(charlie), 1);
    }
}

contract Test_NativeTokenWrapper_mintWithNative is NativeTokenWrapperTest {
    function test_RevertWhen_NotAllowed() public {
        vm.deal(bob, 10 ether);

        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.mintWithNative{ value: 5 ether }();
    }

    function test_Success_AllowedAddress() public {
        // First, allow bob
        vm.prank(alice);
        wrapper.toggleAllowance(bob);

        vm.deal(bob, 10 ether);
        uint256 wrapperBalanceBefore = address(wrapper).balance;

        vm.prank(bob);
        wrapper.mintWithNative{ value: 5 ether }();

        assertEq(wrapper.balanceOf(bob), 5 ether);
        assertEq(address(wrapper).balance, wrapperBalanceBefore + 5 ether);
    }

    function test_Success_Minter() public {
        vm.deal(alice, 10 ether);
        uint256 wrapperBalanceBefore = address(wrapper).balance;

        vm.prank(alice);
        wrapper.mintWithNative{ value: 3 ether }();

        assertEq(wrapper.balanceOf(alice), 3 ether);
        assertEq(address(wrapper).balance, wrapperBalanceBefore + 3 ether);
    }
}

contract Test_NativeTokenWrapper_BeforeTokenTransfer is NativeTokenWrapperTest {
    function setUp() public override {
        super.setUp();

        // Mint tokens to distributor
        vm.prank(alice);
        wrapper.mint(address(mockDistributor), 10 ether);
    }

    function test_Success_TransferFromDistributorSendsETH() public {
        uint256 bobETHBefore = bob.balance;
        uint256 wrapperETHBefore = address(wrapper).balance;

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 2 ether);

        // Bob should receive ETH
        assertEq(bob.balance, bobETHBefore + 2 ether);
        assertEq(address(wrapper).balance, wrapperETHBefore - 2 ether);
        // Bob should not keep the wrapper tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_TransferToFeeRecipientSendsETH() public {
        // Mint tokens to alice
        vm.prank(alice);
        wrapper.mint(alice, 5 ether);

        uint256 feeRecipientETHBefore = address(mockFeeRecipient).balance;
        uint256 wrapperETHBefore = address(wrapper).balance;

        vm.prank(alice);
        wrapper.transfer(address(mockFeeRecipient), 1 ether);

        // Fee recipient should receive ETH
        assertEq(address(mockFeeRecipient).balance, feeRecipientETHBefore + 1 ether);
        assertEq(address(wrapper).balance, wrapperETHBefore - 1 ether);
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }

    function test_RevertWhen_RecipientCannotReceiveETH() public {
        MockNonPayable nonPayable = new MockNonPayable();

        vm.expectRevert(Errors.WithdrawalFailed.selector);
        vm.prank(address(mockDistributor));
        wrapper.transfer(address(nonPayable), 1 ether);
    }

    function test_Success_NormalTransferDoesNotSendETH() public {
        // Mint to alice and bob (both allowed)
        vm.prank(alice);
        wrapper.mint(bob, 5 ether);

        uint256 charlieETHBefore = charlie.balance;
        uint256 wrapperETHBefore = address(wrapper).balance;

        // Allow charlie to receive tokens
        vm.prank(alice);
        wrapper.toggleAllowance(charlie);

        vm.prank(bob);
        wrapper.transfer(charlie, 2 ether);

        // Charlie should NOT receive ETH (only from distributor or to feeRecipient)
        assertEq(charlie.balance, charlieETHBefore);
        assertEq(address(wrapper).balance, wrapperETHBefore);
        // Charlie should keep the tokens since he's allowed
        assertEq(wrapper.balanceOf(charlie), 2 ether);
    }
}

contract Test_NativeTokenWrapper_AfterTokenTransfer is NativeTokenWrapperTest {
    function test_Success_BurnsTokensForNonAllowedRecipient() public {
        // Mint to alice
        vm.prank(alice);
        wrapper.mint(alice, 10 ether);

        // Transfer to bob who is not allowed
        vm.prank(alice);
        wrapper.transfer(bob, 5 ether);

        // Bob should have 0 tokens (burned in afterTokenTransfer)
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.totalSupply(), 5 ether); // Only alice's remaining tokens
    }

    function test_Success_KeepsTokensForAllowedRecipient() public {
        // Allow charlie
        vm.prank(alice);
        wrapper.toggleAllowance(charlie);

        // Mint to alice
        vm.prank(alice);
        wrapper.mint(alice, 10 ether);

        // Transfer to charlie who is allowed
        vm.prank(alice);
        wrapper.transfer(charlie, 5 ether);

        // Charlie should keep the tokens
        assertEq(wrapper.balanceOf(charlie), 5 ether);
        assertEq(wrapper.totalSupply(), 10 ether);
    }
}

contract Test_NativeTokenWrapper_SetMinter is NativeTokenWrapperTest {
    function test_RevertWhen_NotMinterOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setMinter(charlie);
    }

    function test_Success_Minter() public {
        vm.prank(alice);
        wrapper.setMinter(bob);

        assertEq(wrapper.minter(), bob);
        assertEq(wrapper.isAllowed(alice), 0); // Old minter no longer allowed
        assertEq(wrapper.isAllowed(bob), 1); // New minter is allowed
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setMinter(charlie);

        assertEq(wrapper.minter(), charlie);
        assertEq(wrapper.isAllowed(alice), 0);
        assertEq(wrapper.isAllowed(charlie), 1);
    }
}

contract Test_NativeTokenWrapper_ToggleAllowance is NativeTokenWrapperTest {
    function test_RevertWhen_NotMinterOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.toggleAllowance(charlie);
    }

    function test_Success_Minter() public {
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

        vm.prank(governor);
        wrapper.toggleAllowance(charlie);
        assertEq(wrapper.isAllowed(charlie), 0);
    }
}

contract Test_NativeTokenWrapper_Recover is NativeTokenWrapperTest {
    function test_RevertWhen_NotMinterOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.recover(address(angle), bob, 1 ether);
    }

    function test_Success_Minter() public {
        // Send some tokens to wrapper
        angle.mint(address(wrapper), 10 ether);

        uint256 bobBalanceBefore = angle.balanceOf(bob);

        vm.prank(alice);
        wrapper.recover(address(angle), bob, 5 ether);

        assertEq(angle.balanceOf(bob), bobBalanceBefore + 5 ether);
        assertEq(angle.balanceOf(address(wrapper)), 5 ether);
    }

    function test_Success_Governor() public {
        agEUR.mint(address(wrapper), 20 ether);

        uint256 charlieBalanceBefore = agEUR.balanceOf(charlie);

        vm.prank(governor);
        wrapper.recover(address(agEUR), charlie, 10 ether);

        assertEq(agEUR.balanceOf(charlie), charlieBalanceBefore + 10 ether);
        assertEq(agEUR.balanceOf(address(wrapper)), 10 ether);
    }
}

contract Test_NativeTokenWrapper_RecoverETH is NativeTokenWrapperTest {
    function test_RevertWhen_NotMinterOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.recoverETH(payable(bob), 1 ether);
    }

    function test_Success_Minter() public {
        uint256 bobBalanceBefore = bob.balance;
        uint256 wrapperBalanceBefore = address(wrapper).balance;

        vm.prank(alice);
        wrapper.recoverETH(payable(bob), 5 ether);

        assertEq(bob.balance, bobBalanceBefore + 5 ether);
        assertEq(address(wrapper).balance, wrapperBalanceBefore - 5 ether);
    }

    function test_Success_Governor() public {
        uint256 charlieBalanceBefore = charlie.balance;
        uint256 wrapperBalanceBefore = address(wrapper).balance;

        vm.prank(governor);
        wrapper.recoverETH(payable(charlie), 10 ether);

        assertEq(charlie.balance, charlieBalanceBefore + 10 ether);
        assertEq(address(wrapper).balance, wrapperBalanceBefore - 10 ether);
    }

    function test_RevertWhen_RecipientCannotReceiveETH() public {
        MockNonPayable nonPayable = new MockNonPayable();

        vm.expectRevert(Errors.WithdrawalFailed.selector);
        vm.prank(alice);
        wrapper.recoverETH(payable(address(nonPayable)), 1 ether);
    }
}

contract Test_NativeTokenWrapper_SetFeeRecipient is NativeTokenWrapperTest {
    function test_Success() public {
        address newFeeRecipient = vm.addr(999);

        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(newFeeRecipient));

        wrapper.setFeeRecipient();

        assertEq(wrapper.feeRecipient(), newFeeRecipient);
    }
}

contract Test_NativeTokenWrapper_Decimals is NativeTokenWrapperTest {
    function test_Success_Returns18() public {
        assertEq(wrapper.decimals(), 18);
    }
}

contract Test_NativeTokenWrapper_Integration is NativeTokenWrapperTest {
    function test_Integration_CompleteFlow() public {
        // 1. User sends ETH and mints wrapper tokens
        vm.prank(alice);
        wrapper.toggleAllowance(bob);

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        wrapper.mintWithNative{ value: 5 ether }();

        assertEq(wrapper.balanceOf(bob), 5 ether);
        assertEq(address(wrapper).balance, 105 ether); // 100 initial + 5 minted

        // 2. Bob creates a campaign by transferring to distributor
        vm.prank(bob);
        wrapper.transfer(address(mockDistributor), 3 ether);

        assertEq(wrapper.balanceOf(address(mockDistributor)), 3 ether);
        assertEq(wrapper.balanceOf(bob), 2 ether);

        // 3. Distributor distributes rewards (sends native ETH to recipient)
        uint256 charlieETHBefore = charlie.balance;

        vm.prank(address(mockDistributor));
        wrapper.transfer(charlie, 2 ether);

        // Charlie receives ETH (not wrapper tokens, they get burned)
        assertEq(charlie.balance, charlieETHBefore + 2 ether);
        assertEq(wrapper.balanceOf(charlie), 0);
        assertEq(address(wrapper).balance, 103 ether); // 105 - 2 sent to charlie

        // 4. Check remaining distributor balance
        assertEq(wrapper.balanceOf(address(mockDistributor)), 1 ether);
    }
}
