// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { MezoWrapper, IMezoStaking } from "../../../../contracts/partners/tokenWrappers/MezoWrapper.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient } from "./TokenWrapperMocks.sol";

/// @dev Mock Mezo staking contract that records lock calls and pulls tokens from the caller
contract MockMezoStaking {
    struct LockCall {
        uint256 value;
        uint256 lockDuration;
        address to;
    }

    LockCall[] public lockCalls;
    IERC20 public token;
    uint256 public nextLockId;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function createLockFor(uint256 _value, uint256 _lockDuration, address _to) external returns (uint256) {
        token.transferFrom(msg.sender, address(this), _value);
        lockCalls.push(LockCall(_value, _lockDuration, _to));
        return nextLockId++;
    }

    function lockCallsLength() external view returns (uint256) {
        return lockCalls.length;
    }
}

contract MezoWrapperTest is Fixture {
    MezoWrapper public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;
    MockMezoStaking public mockMezoStaking;

    uint256 public constant LOCK_DURATION = 30 days;

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();
        mockMezoStaking = new MockMezoStaking(address(angle));

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new MezoWrapper(
            address(angle),
            address(creator),
            alice,
            address(mockMezoStaking),
            LOCK_DURATION,
            "Mezo Locked ANGLE",
            "mlANGLE"
        );

        mockDistributor.setWrapper(address(wrapper));

        angle.mint(alice, 1000 ether);

        vm.prank(alice);
        angle.approve(address(wrapper), type(uint256).max);
    }
}

contract Test_MezoWrapper_Constructor is MezoWrapperTest {
    function test_RevertWhen_ZeroAddressMezoStaking() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new MezoWrapper(address(angle), address(creator), alice, address(0), LOCK_DURATION, "Test", "TST");
    }

    function test_Success_StateSetCorrectly() public {
        assertEq(wrapper.name(), "Mezo Locked ANGLE");
        assertEq(wrapper.symbol(), "mlANGLE");
        assertEq(wrapper.token(), address(angle));
        assertEq(wrapper.holder(), alice);
        assertEq(wrapper.mezoStaking(), address(mockMezoStaking));
        assertEq(wrapper.lockDuration(), LOCK_DURATION);
        assertEq(address(wrapper.accessControlManager()), address(accessControlManager));
        assertEq(wrapper.distributor(), address(mockDistributor));
        assertEq(wrapper.distributionCreator(), address(creator));
        assertEq(wrapper.feeRecipient(), address(mockFeeRecipient));
        assertEq(wrapper.decimals(), angle.decimals());
        assertEq(angle.allowance(address(wrapper), address(mockMezoStaking)), type(uint256).max);
    }
}

contract Test_MezoWrapper_BeforeTokenTransfer is MezoWrapperTest {
    function setUp() public override {
        super.setUp();

        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 100 ether);
    }

    function test_Success_ClaimCreatesLockForRecipient() public {
        uint256 aliceAngleBefore = angle.balanceOf(alice);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        // Tokens pulled from holder and locked in Mezo staking
        assertEq(angle.balanceOf(alice), aliceAngleBefore - 20 ether);
        assertEq(angle.balanceOf(address(mockMezoStaking)), 20 ether);

        // Lock was created with correct params
        assertEq(mockMezoStaking.lockCallsLength(), 1);
        (uint256 value, uint256 duration, address to) = mockMezoStaking.lockCalls(0);
        assertEq(value, 20 ether);
        assertEq(duration, LOCK_DURATION);
        assertEq(to, bob);

        // Wrapper tokens burned for non-allowed recipient
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_FeeTransferCreatesLock() public {
        uint256 aliceAngleBefore = angle.balanceOf(alice);

        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(angle.balanceOf(alice), aliceAngleBefore - 10 ether);
        assertEq(angle.balanceOf(address(mockMezoStaking)), 10 ether);

        assertEq(mockMezoStaking.lockCallsLength(), 1);
        (uint256 value, uint256 duration, address to) = mockMezoStaking.lockCalls(0);
        assertEq(value, 10 ether);
        assertEq(duration, LOCK_DURATION);
        assertEq(to, address(mockFeeRecipient));
    }

    function test_Success_NormalTransferDoesNotCreateLock() public {
        uint256 aliceAngleBefore = angle.balanceOf(alice);

        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(bob, 50 ether);

        assertEq(angle.balanceOf(alice), aliceAngleBefore);
        assertEq(mockMezoStaking.lockCallsLength(), 0);
        assertEq(wrapper.balanceOf(bob), 0);
    }

    function test_Success_MultipleClaims() public {
        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 20 ether);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 30 ether);

        assertEq(mockMezoStaking.lockCallsLength(), 2);

        (uint256 value0, uint256 duration0, address to0) = mockMezoStaking.lockCalls(0);
        assertEq(value0, 20 ether);
        assertEq(duration0, LOCK_DURATION);
        assertEq(to0, bob);

        (uint256 value1, uint256 duration1, address to1) = mockMezoStaking.lockCalls(1);
        assertEq(value1, 30 ether);
        assertEq(duration1, LOCK_DURATION);
        assertEq(to1, charlie);

        assertEq(angle.balanceOf(address(mockMezoStaking)), 50 ether);
    }

    function test_RevertWhen_HolderHasInsufficientTokens() public {
        uint256 aliceBalance = angle.balanceOf(alice);
        vm.prank(alice);
        angle.transfer(address(1), aliceBalance);

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

contract Test_MezoWrapper_SetLockDuration is MezoWrapperTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setLockDuration(60 days);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.setLockDuration(60 days);

        assertEq(wrapper.lockDuration(), 60 days);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setLockDuration(90 days);

        assertEq(wrapper.lockDuration(), 90 days);
    }

    function test_Success_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit MezoWrapper.LockDurationUpdated(60 days);

        vm.prank(alice);
        wrapper.setLockDuration(60 days);
    }

    function test_Success_NewDurationUsedOnClaim() public {
        vm.prank(alice);
        wrapper.setLockDuration(90 days);

        vm.prank(alice);
        wrapper.mint(alice, 50 ether);
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 50 ether);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 10 ether);

        (, uint256 duration, ) = mockMezoStaking.lockCalls(0);
        assertEq(duration, 90 days);
    }
}

contract Test_MezoWrapper_SetStakingAllowance is MezoWrapperTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setStakingAllowance(100 ether);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.setStakingAllowance(500 ether);

        assertEq(angle.allowance(address(wrapper), address(mockMezoStaking)), 500 ether);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setStakingAllowance(1000 ether);

        assertEq(angle.allowance(address(wrapper), address(mockMezoStaking)), 1000 ether);
    }

    function test_Success_ResetToMax() public {
        vm.prank(alice);
        wrapper.setStakingAllowance(100 ether);
        assertEq(angle.allowance(address(wrapper), address(mockMezoStaking)), 100 ether);

        vm.prank(alice);
        wrapper.setStakingAllowance(type(uint256).max);
        assertEq(angle.allowance(address(wrapper), address(mockMezoStaking)), type(uint256).max);
    }
}

contract Test_MezoWrapper_Integration is MezoWrapperTest {
    function test_Integration_CompleteFlow() public {
        // 1. Holder mints wrapper tokens
        vm.prank(alice);
        wrapper.mint(alice, 100 ether);

        assertEq(wrapper.balanceOf(alice), 100 ether);

        // 2. Holder transfers wrapper tokens to distributor
        vm.prank(alice);
        wrapper.transfer(address(mockDistributor), 80 ether);

        assertEq(wrapper.balanceOf(address(mockDistributor)), 80 ether);
        assertEq(wrapper.balanceOf(alice), 20 ether);

        // 3. Distributor distributes rewards — tokens pulled from holder, locked in Mezo
        vm.prank(address(mockDistributor));
        wrapper.transfer(bob, 30 ether);

        assertEq(angle.balanceOf(address(mockMezoStaking)), 30 ether);
        assertEq(wrapper.balanceOf(bob), 0);

        // 4. Distributor sends fees — also locked in Mezo
        vm.prank(address(mockDistributor));
        wrapper.transfer(address(mockFeeRecipient), 10 ether);

        assertEq(angle.balanceOf(address(mockMezoStaking)), 40 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 40 ether);

        // 5. Verify all locks
        assertEq(mockMezoStaking.lockCallsLength(), 2);

        // 6. Owner changes lock duration for future claims
        vm.prank(alice);
        wrapper.setLockDuration(90 days);

        vm.prank(address(mockDistributor));
        wrapper.transfer(charlie, 15 ether);

        (, uint256 duration, ) = mockMezoStaking.lockCalls(2);
        assertEq(duration, 90 days);
        assertEq(mockMezoStaking.lockCallsLength(), 3);
    }
}
