// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

import { NativeTokenUnwrapperImmutable } from "../../../../contracts/partners/tokenWrappers/NativeTokenUnwrapperImmutable.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient, MockNonPayable } from "./TokenWrapperMocks.sol";
import { MockTokenPermit } from "../../../../contracts/mock/MockTokenPermit.sol";

/// @dev Mock WETH: wraps/unwraps ETH like the real WETH contract
contract MockWETH is MockTokenPermit {
    constructor() MockTokenPermit("Wrapped Ether", "WETH", 18) {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        _burn(msg.sender, wad);
        (bool success, ) = msg.sender.call{ value: wad }("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {}
}

contract NativeTokenUnwrapperImmutableTest is Fixture {
    NativeTokenUnwrapperImmutable public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;
    MockWETH public weth;

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();
        weth = new MockWETH();

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new NativeTokenUnwrapperImmutable(address(weth), address(creator), alice, "Ether", "ETH");

        mockDistributor.setWrapper(address(wrapper));
    }
}

contract Test_NativeTokenUnwrapperImmutable_Constructor is NativeTokenUnwrapperImmutableTest {
    function test_Success() public {
        assertEq(wrapper.name(), "Ether");
        assertEq(wrapper.symbol(), "ETH");
        assertEq(wrapper.token(), address(weth));
        assertEq(wrapper.holder(), alice);
        assertEq(address(wrapper.accessControlManager()), address(accessControlManager));
        assertEq(wrapper.distributor(), address(mockDistributor));
        assertEq(wrapper.distributionCreator(), address(creator));
        assertEq(wrapper.decimals(), 18);
        assertEq(wrapper.feeRecipient(), address(mockFeeRecipient));
        assertTrue(wrapper.isTokenWrapper());
    }
}

contract Test_NativeTokenUnwrapperImmutable_MintPath is NativeTokenUnwrapperImmutableTest {
    function test_Success_AnyoneCanMintToDistributor() public {
        // Bob gets some WETH
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        weth.deposit{ value: 10 ether }();

        // Bob approves wrapper and transfers to distributor
        vm.prank(bob);
        weth.approve(address(wrapper), 5 ether);
        vm.prank(bob);
        wrapper.approve(address(wrapper), 5 ether);

        vm.prank(bob);
        wrapper.transfer(address(mockDistributor), 5 ether);

        // WETH should be on the wrapper contract
        assertEq(weth.balanceOf(address(wrapper)), 5 ether);
        // Distributor should hold wrapper tokens
        assertEq(wrapper.balanceOf(address(mockDistributor)), 5 ether);
        // Bob should have no wrapper tokens (not allowed, burned in afterTokenTransfer... but bob is the from, not to)
        // Actually bob sent them to distributor, so bob's balance reduced by 5 but the _mint gave him 5 first
        // The flow: _beforeTokenTransfer mints 5 to bob, then the transfer sends 5 from bob to distributor
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_MintToFeeRecipient() public {
        // Bob gets some WETH
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        weth.deposit{ value: 10 ether }();

        vm.prank(bob);
        weth.approve(address(wrapper), 3 ether);

        vm.prank(bob);
        wrapper.transfer(address(mockFeeRecipient), 3 ether);

        // WETH should have gone directly to fee recipient
        assertEq(weth.balanceOf(address(mockFeeRecipient)), 3 ether);
        assertEq(weth.balanceOf(address(wrapper)), 0);
        // Wrapper tokens burned for fee recipient (not allowed)
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }
}

contract Test_NativeTokenUnwrapperImmutable_ClaimPath is NativeTokenUnwrapperImmutableTest {
    function setUp() public override {
        super.setUp();

        // Fund: alice deposits WETH and sends wrapper tokens to distributor
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        weth.deposit{ value: 100 ether }();

        vm.prank(alice);
        weth.approve(address(wrapper), 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);
    }

    function test_Success_ClaimUnwrapsToNative() public {
        uint256 bobETHBefore = bob.balance;

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        // Bob receives native ETH
        assertEq(bob.balance, bobETHBefore + 20 ether);
        // Wrapper tokens burned (bob not allowed)
        assertEq(wrapper.balanceOf(bob), 0);
        // WETH balance on wrapper decreased
        assertEq(weth.balanceOf(address(wrapper)), 80 ether);
    }

    function test_Success_MultipleClaimsWork() public {
        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 10 ether);
        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 25 ether);

        assertEq(bob.balance, 10 ether);
        assertEq(charlie.balance, 25 ether);
        assertEq(weth.balanceOf(address(wrapper)), 65 ether);
    }

    function test_RevertWhen_RecipientCannotReceiveETH() public {
        MockNonPayable nonPayable = new MockNonPayable();

        vm.expectRevert(Errors.WithdrawalFailed.selector);
        vm.prank(address(mockDistributor));
        wrapper.transfer(address(nonPayable), 1 ether);
    }
}

contract Test_NativeTokenUnwrapperImmutable_Burn is NativeTokenUnwrapperImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.prank(alice);
        wrapper.mint(alice, 10 ether);

        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.burn(alice, 5 ether);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.mint(alice, 10 ether);

        vm.prank(alice);
        wrapper.burn(alice, 5 ether);

        assertEq(wrapper.balanceOf(alice), 5 ether);
    }

    function test_Success_Governor() public {
        vm.prank(alice);
        wrapper.mint(alice, 10 ether);

        vm.prank(governor);
        wrapper.burn(alice, 3 ether);

        assertEq(wrapper.balanceOf(alice), 7 ether);
    }
}

contract Test_NativeTokenUnwrapperImmutable_RecoverETH is NativeTokenUnwrapperImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.deal(address(wrapper), 10 ether);

        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.recoverETH(payable(bob), 5 ether);
    }

    function test_Success_Holder() public {
        vm.deal(address(wrapper), 10 ether);
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        wrapper.recoverETH(payable(bob), 5 ether);

        assertEq(bob.balance, bobBefore + 5 ether);
        assertEq(address(wrapper).balance, 5 ether);
    }

    function test_RevertWhen_RecipientCannotReceiveETH() public {
        vm.deal(address(wrapper), 10 ether);
        MockNonPayable nonPayable = new MockNonPayable();

        vm.expectRevert(Errors.WithdrawalFailed.selector);
        vm.prank(alice);
        wrapper.recoverETH(payable(address(nonPayable)), 1 ether);
    }
}

contract Test_NativeTokenUnwrapperImmutable_ReceiveETH is NativeTokenUnwrapperImmutableTest {
    function test_Success_CanReceiveETH() public {
        vm.deal(bob, 5 ether);
        vm.prank(bob);
        (bool success, ) = address(wrapper).call{ value: 3 ether }("");

        assertTrue(success);
        assertEq(address(wrapper).balance, 3 ether);
    }
}

contract Test_NativeTokenUnwrapperImmutable_Integration is NativeTokenUnwrapperImmutableTest {
    function test_Integration_CompleteFlow() public {
        // 1. Bob gets WETH and funds the distributor permissionlessly
        vm.deal(bob, 50 ether);
        vm.prank(bob);
        weth.deposit{ value: 50 ether }();

        vm.prank(bob);
        weth.approve(address(wrapper), 50 ether);

        vm.prank(bob);
        wrapper.transfer(address(mockDistributor), 50 ether);

        assertEq(weth.balanceOf(address(wrapper)), 50 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 50 ether);

        // 2. Charlie claims and receives native ETH
        uint256 charlieETHBefore = charlie.balance;

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 15 ether);

        assertEq(charlie.balance, charlieETHBefore + 15 ether);
        assertEq(wrapper.balanceOf(charlie), 0);
        assertEq(weth.balanceOf(address(wrapper)), 35 ether);

        // 3. Dylan also claims
        uint256 dylanETHBefore = dylan.balance;

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(dylan, 10 ether);

        assertEq(dylan.balance, dylanETHBefore + 10 ether);
        assertEq(weth.balanceOf(address(wrapper)), 25 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 25 ether);
    }
}
