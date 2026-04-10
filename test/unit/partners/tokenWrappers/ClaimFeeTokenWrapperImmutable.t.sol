// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

import { ClaimFeeTokenWrapperImmutable } from "../../../../contracts/partners/tokenWrappers/ClaimFeeTokenWrapperImmutable.sol";
import { Fixture } from "../../../Fixture.t.sol";
import { Errors } from "../../../../contracts/utils/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockDistributor, MockFeeRecipient } from "./TokenWrapperMocks.sol";

contract ClaimFeeTokenWrapperImmutableTest is Fixture {
    ClaimFeeTokenWrapperImmutable public wrapper;
    MockDistributor public mockDistributor;
    MockFeeRecipient public mockFeeRecipient;
    address public claimFeeRecipient;

    uint256 public constant CLAIM_FEE_RATE = 5e7; // 5%
    uint256 public constant BASE = 1e9;

    function setUp() public virtual override {
        super.setUp();

        mockDistributor = new MockDistributor();
        mockFeeRecipient = new MockFeeRecipient();
        claimFeeRecipient = dylan;

        vm.mockCall(address(creator), abi.encodeWithSignature("distributor()"), abi.encode(address(mockDistributor)));
        vm.mockCall(address(creator), abi.encodeWithSignature("feeRecipient()"), abi.encode(address(mockFeeRecipient)));

        wrapper = new ClaimFeeTokenWrapperImmutable(
            address(angle),
            address(creator),
            alice,
            CLAIM_FEE_RATE,
            claimFeeRecipient
        );

        mockDistributor.setWrapper(address(wrapper));
    }
}

contract Test_ClaimFeeTokenWrapperImmutable_Constructor is ClaimFeeTokenWrapperImmutableTest {
    function test_Success() public {
        assertEq(wrapper.name(), string(abi.encodePacked(angle.name(), " (wrapped)")));
        assertEq(wrapper.symbol(), angle.symbol());
        assertEq(wrapper.token(), address(angle));
        assertEq(wrapper.holder(), alice);
        assertEq(address(wrapper.accessControlManager()), address(accessControlManager));
        assertEq(wrapper.distributor(), address(mockDistributor));
        assertEq(wrapper.distributionCreator(), address(creator));
        assertEq(wrapper.feeRecipient(), address(mockFeeRecipient));
        assertEq(wrapper.claimFeeRate(), CLAIM_FEE_RATE);
        assertEq(wrapper.claimFeeRecipient(), claimFeeRecipient);
        assertTrue(wrapper.isTokenWrapper());
    }

    function test_RevertWhen_FeeRateTooHigh() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        new ClaimFeeTokenWrapperImmutable(
            address(angle),
            address(creator),
            alice,
            BASE, // 100%, should revert
            claimFeeRecipient
        );
    }

    function test_RevertWhen_ZeroFeeRecipient() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ClaimFeeTokenWrapperImmutable(
            address(angle),
            address(creator),
            alice,
            CLAIM_FEE_RATE,
            address(0)
        );
    }
}

contract Test_ClaimFeeTokenWrapperImmutable_MintPath is ClaimFeeTokenWrapperImmutableTest {
    function test_Success_AnyoneCanMintToDistributor() public {
        angle.mint(bob, 10 ether);

        vm.prank(bob);
        angle.approve(address(wrapper), 5 ether);

        vm.prank(bob);
        wrapper.transfer(address(mockDistributor), 5 ether);

        // Underlying should be on the wrapper contract
        assertEq(angle.balanceOf(address(wrapper)), 5 ether);
        // Distributor should hold wrapper tokens
        assertEq(wrapper.balanceOf(address(mockDistributor)), 5 ether);
    }

    function test_Success_MintToMerklFeeRecipient() public {
        angle.mint(bob, 10 ether);

        vm.prank(bob);
        angle.approve(address(wrapper), 3 ether);

        vm.prank(bob);
        wrapper.transfer(address(mockFeeRecipient), 3 ether);

        // Underlying should have gone directly to fee recipient
        assertEq(angle.balanceOf(address(mockFeeRecipient)), 3 ether);
        assertEq(angle.balanceOf(address(wrapper)), 0);
        // Wrapper tokens burned (fee recipient not allowed)
        assertEq(wrapper.balanceOf(address(mockFeeRecipient)), 0);
    }
}

contract Test_ClaimFeeTokenWrapperImmutable_ClaimPath is ClaimFeeTokenWrapperImmutableTest {
    function setUp() public override {
        super.setUp();

        // Fund: bob deposits underlying and sends wrapper tokens to distributor
        angle.mint(bob, 100 ether);
        vm.prank(bob);
        angle.approve(address(wrapper), 100 ether);
        vm.prank(bob);
        wrapper.transfer(address(mockDistributor), 100 ether);
    }

    function test_Success_ClaimWithFee() public {
        uint256 charlieBalanceBefore = angle.balanceOf(charlie);
        uint256 feeRecipientBefore = angle.balanceOf(claimFeeRecipient);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 100 ether);

        // 5% fee = 5 ether to fee recipient, 95 ether to charlie
        uint256 expectedFee = (100 ether * CLAIM_FEE_RATE) / BASE;
        assertEq(angle.balanceOf(charlie), charlieBalanceBefore + 100 ether - expectedFee);
        assertEq(angle.balanceOf(claimFeeRecipient), feeRecipientBefore + expectedFee);
        // Wrapper tokens burned (charlie not allowed)
        assertEq(wrapper.balanceOf(charlie), 0);
    }

    function test_Success_ClaimWithZeroFee() public {
        // Set fee to 0
        vm.prank(alice);
        wrapper.setClaimFeeRate(0);

        uint256 charlieBalanceBefore = angle.balanceOf(charlie);
        uint256 feeRecipientBefore = angle.balanceOf(claimFeeRecipient);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 50 ether);

        // No fee, charlie gets full amount
        assertEq(angle.balanceOf(charlie), charlieBalanceBefore + 50 ether);
        assertEq(angle.balanceOf(claimFeeRecipient), feeRecipientBefore);
    }

    function test_Success_SmallClaimRoundsDownFee() public {
        // Claim 1 wei — fee rounds to 0
        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 1);

        assertEq(angle.balanceOf(charlie), 1);
    }

    function test_Success_MultipleClaimsAccumulateFees() public {
        uint256 feeRecipientBefore = angle.balanceOf(claimFeeRecipient);

        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(bob, 40 ether);
        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 60 ether);

        uint256 expectedFee = (100 ether * CLAIM_FEE_RATE) / BASE;
        assertEq(angle.balanceOf(claimFeeRecipient), feeRecipientBefore + expectedFee);
        assertEq(angle.balanceOf(address(wrapper)), 0);
    }
}

contract Test_ClaimFeeTokenWrapperImmutable_Burn is ClaimFeeTokenWrapperImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        deal(address(wrapper), alice, 10 ether);

        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.burn(alice, 5 ether);
    }

    function test_Success_Holder() public {
        deal(address(wrapper), alice, 10 ether);

        vm.prank(alice);
        wrapper.burn(alice, 5 ether);

        assertEq(wrapper.balanceOf(alice), 5 ether);
    }

    function test_Success_Governor() public {
        deal(address(wrapper), alice, 10 ether);

        vm.prank(governor);
        wrapper.burn(alice, 3 ether);

        assertEq(wrapper.balanceOf(alice), 7 ether);
    }
}

contract Test_ClaimFeeTokenWrapperImmutable_SetClaimFeeRate is ClaimFeeTokenWrapperImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setClaimFeeRate(1e7);
    }

    function test_RevertWhen_FeeRateTooHigh() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(alice);
        wrapper.setClaimFeeRate(BASE);
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.setClaimFeeRate(1e7);

        assertEq(wrapper.claimFeeRate(), 1e7);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setClaimFeeRate(2e8);

        assertEq(wrapper.claimFeeRate(), 2e8);
    }

    function test_Success_SetToZero() public {
        vm.prank(alice);
        wrapper.setClaimFeeRate(0);

        assertEq(wrapper.claimFeeRate(), 0);
    }
}

contract Test_ClaimFeeTokenWrapperImmutable_SetClaimFeeRecipient is ClaimFeeTokenWrapperImmutableTest {
    function test_RevertWhen_NotHolderOrGovernor() public {
        vm.expectRevert(Errors.NotAllowed.selector);
        vm.prank(bob);
        wrapper.setClaimFeeRecipient(charlie);
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(alice);
        wrapper.setClaimFeeRecipient(address(0));
    }

    function test_Success_Holder() public {
        vm.prank(alice);
        wrapper.setClaimFeeRecipient(charlie);

        assertEq(wrapper.claimFeeRecipient(), charlie);
    }

    function test_Success_Governor() public {
        vm.prank(governor);
        wrapper.setClaimFeeRecipient(bob);

        assertEq(wrapper.claimFeeRecipient(), bob);
    }
}

contract Test_ClaimFeeTokenWrapperImmutable_Integration is ClaimFeeTokenWrapperImmutableTest {
    function test_Integration_CompleteFlow() public {
        // 1. Bob funds the distributor permissionlessly
        angle.mint(bob, 100 ether);
        vm.prank(bob);
        angle.approve(address(wrapper), 100 ether);
        vm.prank(bob);
        wrapper.transfer(address(mockDistributor), 100 ether);

        assertEq(angle.balanceOf(address(wrapper)), 100 ether);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 100 ether);

        // 2. Charlie claims 60 ether (5% fee = 3 ether to dylan)
        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(charlie, 60 ether);

        assertEq(angle.balanceOf(charlie), 57 ether);
        assertEq(angle.balanceOf(dylan), 3 ether);
        assertEq(wrapper.balanceOf(charlie), 0);

        // 3. Fee rate is changed to 10%
        vm.prank(alice);
        wrapper.setClaimFeeRate(1e8);

        // 4. Alice claims remaining 40 ether (10% fee = 4 ether to dylan)
        vm.prank(address(mockDistributor));
        mockDistributor.simulateClaim(alice, 40 ether);

        assertEq(angle.balanceOf(alice), 36 ether);
        assertEq(angle.balanceOf(dylan), 3 ether + 4 ether);
        assertEq(angle.balanceOf(address(wrapper)), 0);
        assertEq(wrapper.balanceOf(address(mockDistributor)), 0);
    }
}
