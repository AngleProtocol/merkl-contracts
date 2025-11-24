// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Test } from "forge-std/Test.sol";

import { DistributionCreator, DistributionParameters, CampaignParameters, RewardTokenAmounts } from "../../contracts/DistributionCreator.sol";
import { DistributionCreatorWithDistributions } from "../../contracts/DistributionCreatorWithDistributions.sol";
import { Errors } from "../../contracts/utils/Errors.sol";
import { Fixture, IERC20 } from "../Fixture.t.sol";
import { IAccessControlManager } from "../../contracts/interfaces/IAccessControlManager.sol";

contract DistributionCreatorTest is Fixture {
    using SafeERC20 for IERC20;

    uint256 constant maxDistribForOOG = 1e4;
    uint256 constant nbrDistrib = 10;
    uint32 initStartTime;
    uint32 initEndTime;
    uint32 startTime;
    uint32 endTime;
    uint32 numEpoch;
    address[] positionWrappers = new address[](3);
    uint32[] wrapperTypes = new uint32[](3);

    function setUp() public virtual override {
        super.setUp();

        initStartTime = uint32(block.timestamp) + 1;
        numEpoch = 25;
        initEndTime = startTime + numEpoch * EPOCH_DURATION;

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(angle);
        amounts[0] = 1e8;

        vm.startPrank(guardian);
        creator.setRewardTokenMinAmounts(tokens, amounts);
        vm.stopPrank();

        angle.mint(address(alice), 1e22);
        vm.prank(alice);
        angle.approve(address(creator), type(uint256).max);

        positionWrappers[0] = alice;
        positionWrappers[1] = bob;
        positionWrappers[2] = charlie;
        wrapperTypes[0] = 0;
        wrapperTypes[1] = 1;
        wrapperTypes[2] = 3;

        vm.startPrank(alice);
        // struct DistributionParameters memory
        // create a bunch of distributions to make the view function call fail
        DistributionParameters memory params = DistributionParameters({
            uniV3Pool: address(pool),
            rewardToken: address(angle),
            positionWrappers: positionWrappers,
            wrapperTypes: wrapperTypes,
            amount: 1e10,
            propToken0: 4000,
            propToken1: 2000,
            propFees: 4000,
            isOutOfRangeIncentivized: 0,
            epochStart: initStartTime,
            numEpoch: 25,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });
        // create a first distrib way before the others
        creator.createDistribution(params);

        for (uint256 i; i < nbrDistrib; i++) {
            vm.warp(startTime + 3600 * 24 * 1000);
            startTime = uint32(startTime + 3600 * 24 * 1000);
            endTime = startTime + numEpoch * EPOCH_DURATION;
            params.epochStart = startTime;
            creator.createDistribution(params);
        }
        vm.warp(startTime + 3600 * 24 * 1000);

        vm.stopPrank();
    }
}

contract Test_DistributionCreator_Initialize is DistributionCreatorTest {
    DistributionCreatorWithDistributions d;

    function setUp() public override {
        super.setUp();
        d = DistributionCreatorWithDistributions(deployUUPS(address(new DistributionCreatorWithDistributions()), hex""));
    }

    function test_RevertWhen_CalledOnImplem() public {
        vm.expectRevert("Initializable: contract is already initialized");
        creatorImpl.initialize(IAccessControlManager(address(0)), address(bob), 1e8);
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        d.initialize(IAccessControlManager(address(0)), address(bob), 1e8);

        vm.expectRevert(Errors.ZeroAddress.selector);
        d.initialize(IAccessControlManager(address(accessControlManager)), address(0), 1e8);
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        d.initialize(IAccessControlManager(address(accessControlManager)), address(bob), 1e9);
    }

    function test_Success() public {
        d.initialize(IAccessControlManager(address(accessControlManager)), address(bob), 1e8);

        assertEq(address(d.distributor()), address(bob));
        assertEq(address(d.accessControlManager()), address(accessControlManager));
        assertEq(d.defaultFees(), 1e8);
    }
}

contract Test_DistributionCreator_CreateDistribution is DistributionCreatorTest {
    function test_RevertWhen_CampaignDurationIsZero() public {
        DistributionParameters memory distribution = DistributionParameters({
            uniV3Pool: address(pool),
            rewardToken: address(angle),
            positionWrappers: positionWrappers,
            wrapperTypes: wrapperTypes,
            amount: 1e10,
            propToken0: 4000,
            propToken1: 2000,
            propFees: 4000,
            isOutOfRangeIncentivized: 0,
            epochStart: uint32(block.timestamp + 1),
            numEpoch: 0,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });
        vm.expectRevert(Errors.CampaignDurationBelowHour.selector);

        vm.prank(alice);
        creator.createDistribution(distribution);
    }

    function test_RevertWhen_CampaignRewardTokenNotWhitelisted() public {
        DistributionParameters memory distribution = DistributionParameters({
            uniV3Pool: address(pool),
            rewardToken: address(alice),
            positionWrappers: positionWrappers,
            wrapperTypes: wrapperTypes,
            amount: 1,
            propToken0: 4000,
            propToken1: 2000,
            propFees: 4000,
            isOutOfRangeIncentivized: 0,
            epochStart: uint32(block.timestamp + 1),
            numEpoch: 1,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });
        vm.expectRevert(Errors.CampaignRewardTokenNotWhitelisted.selector);

        vm.prank(alice);
        creator.createDistribution(distribution);
    }

    function test_RevertWhen_CampaignRewardTooLow() public {
        DistributionParameters memory distribution = DistributionParameters({
            uniV3Pool: address(pool),
            rewardToken: address(angle),
            positionWrappers: positionWrappers,
            wrapperTypes: wrapperTypes,
            amount: 1e8 - 1,
            propToken0: 4000,
            propToken1: 2000,
            propFees: 4000,
            isOutOfRangeIncentivized: 0,
            epochStart: uint32(block.timestamp + 1),
            numEpoch: 1,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });
        vm.expectRevert(Errors.CampaignRewardTooLow.selector);

        vm.prank(alice);
        creator.createDistribution(distribution);
    }

    function test_Success() public {
        DistributionParameters memory distribution = DistributionParameters({
            uniV3Pool: address(pool),
            rewardToken: address(angle),
            positionWrappers: positionWrappers,
            wrapperTypes: wrapperTypes,
            amount: 1e10,
            propToken0: 4000,
            propToken1: 2000,
            propFees: 4000,
            isOutOfRangeIncentivized: 0,
            epochStart: uint32(block.timestamp + 2),
            numEpoch: 25,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });

        vm.prank(alice);
        creator.createDistribution(distribution);

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = abi.encode(
            distribution.uniV3Pool,
            distribution.propFees,
            distribution.propToken0,
            distribution.propToken1,
            distribution.isOutOfRangeIncentivized,
            distribution.boostingAddress,
            distribution.boostedReward,
            whitelist,
            blacklist,
            "0x"
        );

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(angle),
                    uint32(2),
                    uint32(distribution.epochStart),
                    uint32(distribution.numEpoch * 3600),
                    extraData
                )
            )
        );
        CampaignParameters memory fetchedCampaign = creator.campaign(campaignId);
        assertEq(alice, fetchedCampaign.creator);
        assertEq(address(angle), fetchedCampaign.rewardToken);
        assertEq(2, fetchedCampaign.campaignType);
        assertEq(distribution.epochStart, fetchedCampaign.startTimestamp);
        assertEq(distribution.numEpoch * 3600, fetchedCampaign.duration);
        assertEq(extraData, fetchedCampaign.campaignData);
        assertEq(campaignId, fetchedCampaign.campaignId);
    }
}

contract Test_DistributionCreator_CreateCampaign is DistributionCreatorTest {
    function test_RevertWhen_CampaignDurationIsZero() public {
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e10,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 0
        });
        vm.expectRevert(Errors.CampaignDurationBelowHour.selector);

        vm.prank(alice);
        creator.createCampaign(campaign);
        (campaign);
    }

    function test_RevertWhen_CampaignRewardTokenNotWhitelisted() public {
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(alice),
            amount: 1e10,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });
        vm.expectRevert(Errors.CampaignRewardTokenNotWhitelisted.selector);

        vm.prank(alice);
        creator.createCampaign(campaign);
    }

    function test_RevertWhen_CampaignRewardTooLow() public {
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e8 - 1,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });
        vm.expectRevert(Errors.CampaignRewardTooLow.selector);

        vm.prank(alice);
        creator.createCampaign(campaign);
    }

    function test_Success() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(alice);
        creator.createCampaign(campaign);

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount); // amount minus 10% fees
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessDifferentCreator() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(bob),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(alice);
        creator.createCampaign(campaign);

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    bob,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(bob, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount); // amount minus 10% fees
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_Succeed_CampaignStartInThePast() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp - 1),
            duration: 3600
        });

        vm.prank(alice);
        creator.createCampaign(campaign);

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount); // amount minus 10% fees
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalance() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFeeRecipient(dylan);

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            uint256 fees = creator.defaultFees();
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10 - amount);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(creator)), creatorBalance - amount);
            assertEq(angle.balanceOf(address(dylan)), (amount * fees) / 1e9);
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount - ((amount * fees) / 1e9));
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount); // amount minus 10% fees
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalanceWithNoFeeRecipient() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFeeRecipient(address(0));

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            uint256 fees = creator.defaultFees();
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10 - amount);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(creator)), creatorBalance - amount + ((amount * fees) / 1e9));
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount - ((amount * fees) / 1e9));
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount); // amount minus 10% fees
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalanceWithNoFees() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFees(0);

        vm.prank(governor);
        creator.setFeeRecipient(dylan);

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10 - amount);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(creator)), creatorBalance - amount);
            assertEq(angle.balanceOf(address(dylan)), 0);
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount);
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq(amount, fetchedAmount);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalanceAndAllowanceWithNoFees() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFees(0);

        vm.prank(governor);
        creator.setFeeRecipient(dylan);

        angle.mint(address(charlie), 1e10);
        vm.prank(charlie);
        angle.approve(address(creator), type(uint256).max);

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            creator.increaseTokenAllowance(alice, charlie, address(angle), 1e11);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e11);
            vm.stopPrank();

            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 charlieBalance = angle.balanceOf(address(charlie));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            vm.prank(charlie);
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10 - amount);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e11 - amount);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(charlie)), charlieBalance);
            assertEq(angle.balanceOf(address(creator)), creatorBalance - amount);
            assertEq(angle.balanceOf(address(dylan)), 0);
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount);
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq(amount, fetchedAmount);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalanceAndNoAllowanceWithNoFees() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFees(0);

        vm.prank(governor);
        creator.setFeeRecipient(dylan);

        angle.mint(address(charlie), 1e10);
        vm.prank(charlie);
        angle.approve(address(creator), type(uint256).max);

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            creator.increaseTokenAllowance(alice, charlie, address(angle), 1e7);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e7);
            vm.stopPrank();

            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 charlieBalance = angle.balanceOf(address(charlie));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            vm.prank(charlie);
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e7);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(charlie)), charlieBalance - amount);
            assertEq(angle.balanceOf(address(creator)), creatorBalance);
            assertEq(angle.balanceOf(address(dylan)), 0);
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount);
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq(amount, fetchedAmount);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalanceAndNoAllowanceWithFees() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFeeRecipient(dylan);

        angle.mint(address(charlie), 1e10);
        vm.prank(charlie);
        angle.approve(address(creator), type(uint256).max);

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            creator.increaseTokenAllowance(alice, charlie, address(angle), 1e7);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e7);
            vm.stopPrank();

            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 charlieBalance = angle.balanceOf(address(charlie));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            vm.prank(charlie);
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e7);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(charlie)), charlieBalance - amount);
            assertEq(angle.balanceOf(address(creator)), creatorBalance);
            assertEq(angle.balanceOf(address(dylan)), amount / 10);
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount - amount / 10);
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalanceAndNoFeeRecipient() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFeeRecipient(address(0));

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10 - amount);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(creator)), creatorBalance - amount + amount / 10);
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount - amount / 10);
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }

    function test_SuccessFromPreDepositedBalanceAndNoAllowanceWithFeesButNoRecipient() public {
        uint256 amount = 1e8;
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(alice),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: amount,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(governor);
        creator.setFeeRecipient(address(0));

        angle.mint(address(charlie), 1e10);
        vm.prank(charlie);
        angle.approve(address(creator), type(uint256).max);

        {
            vm.startPrank(alice);
            creator.increaseTokenBalance(alice, address(angle), 1e10);
            creator.increaseTokenAllowance(alice, charlie, address(angle), 1e7);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e7);
            vm.stopPrank();

            address distributor = creator.distributor();
            uint256 balance = angle.balanceOf(address(alice));
            uint256 creatorBalance = angle.balanceOf(address(creator));
            uint256 charlieBalance = angle.balanceOf(address(charlie));
            uint256 distributorBalance = angle.balanceOf(address(distributor));
            vm.prank(charlie);
            creator.createCampaign(campaign);
            assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
            assertEq(creator.creatorAllowance(address(alice), address(charlie), address(angle)), 1e7);
            assertEq(angle.balanceOf(address(alice)), balance);
            assertEq(angle.balanceOf(address(charlie)), charlieBalance - amount);
            assertEq(angle.balanceOf(address(creator)), creatorBalance + amount / 10);
            assertEq(angle.balanceOf(address(distributor)), distributorBalance + amount - amount / 10);
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaign.rewardToken),
                    uint32(campaign.campaignType),
                    uint32(campaign.startTimestamp),
                    uint32(campaign.duration),
                    campaign.campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq((amount * 9) / 10, fetchedAmount);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }
}

contract Test_DistributionCreator_CreateCampaigns is DistributionCreatorTest {
    function test_RevertWhen_CampaignAlreadyExists() public {
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e8,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.expectRevert(Errors.CampaignAlreadyExists.selector);

        CampaignParameters[] memory campaigns = new CampaignParameters[](2);
        campaigns[0] = campaign;
        campaigns[1] = campaign;
        vm.prank(alice);
        creator.createCampaigns(campaigns);
    }

    function test_Success() public {
        CampaignParameters[] memory campaigns = new CampaignParameters[](2);
        campaigns[0] = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e8,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });
        campaigns[1] = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e8,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 2),
            duration: 3600
        });
        vm.prank(alice);
        creator.createCampaigns(campaigns);

        // Additional asserts to check for correct behavior
        bytes32 campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaigns[0].rewardToken),
                    uint32(campaigns[0].campaignType),
                    uint32(campaigns[0].startTimestamp),
                    uint32(campaigns[0].duration),
                    campaigns[0].campaignData
                )
            )
        );
        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaigns[0].campaignType, fetchedCampaignType);
        assertEq(campaigns[0].startTimestamp, fetchedStartTimestamp);
        assertEq(campaigns[0].duration, fetchedDuration);
        assertEq(campaigns[0].campaignData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);

        // Additional asserts to check for correct behavior
        campaignId = bytes32(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    alice,
                    address(campaigns[1].rewardToken),
                    uint32(campaigns[1].campaignType),
                    uint32(campaigns[1].startTimestamp),
                    uint32(campaigns[1].duration),
                    campaigns[1].campaignData
                )
            )
        );
        (
            fetchedCampaignId,
            fetchedCreator,
            fetchedRewardToken,
            fetchedAmount,
            fetchedCampaignType,
            fetchedStartTimestamp,
            fetchedDuration,
            fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
        assertEq(alice, fetchedCreator);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaigns[1].campaignType, fetchedCampaignType);
        assertEq(campaigns[1].startTimestamp, fetchedStartTimestamp);
        assertEq(campaigns[1].duration, fetchedDuration);
        assertEq(campaigns[1].campaignData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
    }
}

contract Test_DistributionCreator_setCampaignFees is DistributionCreatorTest {
    event CampaignSpecificFeesSet(uint32 campaignType, uint256 _fees);

    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        vm.prank(alice);
        creator.setCampaignFees(0, 1e8);
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(guardian);
        creator.setCampaignFees(0, 1e10);
    }

    function test_Success() public {
        vm.expectEmit(false, false, false, false, address(creator));
        emit CampaignSpecificFeesSet(0, 5e8);

        vm.prank(guardian);
        creator.setCampaignFees(0, 5e8);

        assertEq(5e8, creator.campaignSpecificFees(0));

        // Now trying to create a campaign
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e8,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 1),
            duration: 3600
        });

        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(campaign);

        (
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));

        assertEq(5e7, fetchedAmount);

        vm.prank(governor);
        creator.setCampaignFees(0, 2e8);

        assertEq(2e8, creator.campaignSpecificFees(0));

        // Now trying to create a campaign
        campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e8,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp + 2),
            duration: 3600
        });

        vm.prank(alice);
        campaignId = creator.createCampaign(campaign);

        (
            fetchedCampaignId,
            fetchedCreator,
            fetchedRewardToken,
            fetchedAmount,
            fetchedCampaignType,
            fetchedStartTimestamp,
            fetchedDuration,
            fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));

        assertEq(8e7, fetchedAmount);
    }
}

contract Test_DistributionCreator_acceptConditions is DistributionCreatorTest {
    function test_Success() public {
        assertEq(creator.userSignatureWhitelist(bob), 0);

        vm.prank(bob);
        creator.acceptConditions();

        bytes32 message;

        assertEq(creator.userSignatures(bob), message);

        string memory newMessage = "merkl terms";

        vm.prank(guardian);
        creator.setMessage(newMessage);

        bytes32 expectedMessage = ECDSA.toEthSignedMessageHash(bytes(newMessage));
        assertEq(creator.messageHash(), expectedMessage);

        vm.prank(bob);
        creator.acceptConditions();
        assertEq(creator.userSignatures(bob), expectedMessage);
    }
}

contract Test_DistributionCreator_setFees is DistributionCreatorTest {
    function test_RevertWhen_NotGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        vm.prank(alice);
        creator.setFees(1e8);
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(governor);
        creator.setFees(1e9);
    }

    function test_Success() public {
        vm.prank(governor);
        creator.setFees(2e8);

        assertEq(creator.defaultFees(), 2e8);
    }
}

contract Test_DistributionCreator_setNewDistributor is DistributionCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        vm.prank(alice);
        creator.setNewDistributor(address(bob));
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(governor);
        creator.setNewDistributor(address(0));
    }

    function test_Success() public {
        vm.prank(governor);
        creator.setNewDistributor(address(bob));

        assertEq(address(creator.distributor()), address(bob));
    }
}

contract Test_DistributionCreator_setUserFeeRebate is DistributionCreatorTest {
    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        vm.prank(alice);
        creator.setUserFeeRebate(alice, 1e8);
    }

    function test_Success() public {
        assertEq(creator.feeRebate(alice), 0);

        vm.prank(governor);
        creator.setUserFeeRebate(alice, 2e8);

        assertEq(creator.feeRebate(alice), 2e8);
    }
}

contract Test_DistributionCreator_setFeeRecipient is DistributionCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        vm.prank(alice);
        creator.setFeeRecipient(address(bob));
    }

    function test_Success() public {
        vm.prank(governor);
        creator.setFeeRecipient(address(bob));

        assertEq(address(creator.feeRecipient()), address(bob));
    }
}

contract Test_DistributionCreator_recoverFees is DistributionCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = angle;

        vm.expectRevert(Errors.NotGovernor.selector);
        vm.prank(alice);
        creator.recoverFees(tokens, address(bob));
    }

    function test_Success() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = angle;

        uint256 balance = angle.balanceOf(address(bob));

        vm.prank(governor);
        creator.recoverFees(tokens, address(bob));

        assertEq(angle.balanceOf(address(bob)), balance + 11e9);
    }
}

contract Test_DistributionCreator_getValidRewardTokens is DistributionCreatorTest {
    function test_Success() public view {
        RewardTokenAmounts[] memory tokens = creator.getValidRewardTokens();

        assertEq(tokens.length, 1);
        assertEq(tokens[0].token, address(angle));
        assertEq(tokens[0].minimumAmountPerEpoch, 1e8);
    }

    function test_SuccessSkip() public view {
        (RewardTokenAmounts[] memory tokens, uint256 i) = creator.getValidRewardTokens(1, 0);

        assertEq(tokens.length, 0);
        assertEq(i, 1);
    }
}

contract DistributionCreatorForkTest is Test {
    DistributionCreatorWithDistributions public creator;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_NODE_URI"));

        creator = DistributionCreatorWithDistributions(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
    }
}

contract Test_DistributionCreator_distribution is DistributionCreatorForkTest {
    function test_Success() public view {
        CampaignParameters memory distribution = creator.distribution(0);

        assertEq(distribution.campaignId, bytes32(0x7570c9deb1660ed82ff01f760b2883edb9bdb881933b0e4085854d0d717ea268));
        assertEq(distribution.creator, address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496));
        assertEq(distribution.rewardToken, address(0xE0688A2FE90d0f93F17f273235031062a210d691));
        assertEq(distribution.amount, 9700000000000000000000);
        assertEq(distribution.campaignType, 2);
        assertEq(distribution.startTimestamp, 1681380000);
        assertEq(distribution.duration, 86400);
        assertEq(
            distribution.campaignData,
            hex"000000000000000000000000149e36e72726e0bcea5c59d40df2c43f60f5a22d0000000000000000000000000000000000000000000000000000000000000bb800000000000000000000000000000000000000000000000000000000000007d000000000000000000000000000000000000000000000000000000000000013880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000023078000000000000000000000000000000000000000000000000000000000000"
        );
    }
}

contract Test_DistributionCreator_adjustTokenBalance is DistributionCreatorTest {
    function test_SuccessWhenUser() public {
        uint256 balance = angle.balanceOf(address(alice));
        uint256 creatorBalance = angle.balanceOf(address(creator));
        vm.startPrank(alice);
        creator.increaseTokenBalance(address(bob), address(angle), 1e9);
        assertEq(creator.creatorBalance(address(bob), address(angle)), 1e9);
        assertEq(angle.balanceOf(address(alice)), balance - 1e9);
        assertEq(angle.balanceOf(address(creator)), creatorBalance + 1e9);
        creator.increaseTokenBalance(address(alice), address(angle), 1e10);
        assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
        assertEq(angle.balanceOf(address(alice)), balance - 1e9 - 1e10);
        assertEq(angle.balanceOf(address(creator)), creatorBalance + 1e9 + 1e10);
        creator.decreaseTokenBalance(address(alice), address(angle), address(alice), 1e10 / 2);
        assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10 / 2);
        assertEq(angle.balanceOf(address(alice)), balance - 1e9 - 1e10 + 1e10 / 2);
        assertEq(angle.balanceOf(address(creator)), creatorBalance + 1e9 + 1e10 - 1e10 / 2);
        creator.decreaseTokenBalance(address(alice), address(angle), address(dylan), 1e9);
        assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10 / 2 - 1e9);
        assertEq(angle.balanceOf(address(dylan)), 1e9);
        vm.stopPrank();
    }

    function test_SuccessWhenGovernor() public {
        uint256 balance = angle.balanceOf(address(alice));
        uint256 balance2 = angle.balanceOf(address(governor));
        uint256 balance3 = angle.balanceOf(address(bob));
        uint256 creatorBalance = angle.balanceOf(address(creator));
        vm.startPrank(governor);
        creator.increaseTokenBalance(address(bob), address(angle), 1e9);
        assertEq(creator.creatorBalance(address(bob), address(angle)), 1e9);
        assertEq(angle.balanceOf(address(governor)), balance2);
        assertEq(angle.balanceOf(address(alice)), balance);
        assertEq(angle.balanceOf(address(bob)), balance3);
        assertEq(angle.balanceOf(address(creator)), creatorBalance);
        creator.increaseTokenBalance(address(alice), address(angle), 1e10);
        assertEq(creator.creatorBalance(address(alice), address(angle)), 1e10);
        assertEq(angle.balanceOf(address(governor)), balance2);
        assertEq(angle.balanceOf(address(alice)), balance);
        assertEq(angle.balanceOf(address(bob)), balance3);
        assertEq(angle.balanceOf(address(creator)), creatorBalance);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = angle;
        creator.recoverFees(tokens, address(bob));
        vm.expectRevert();
        creator.decreaseTokenBalance(address(alice), address(angle), address(alice), 1e10 / 2);
        vm.stopPrank();
    }
    function test_RevertWhenNotUserOrGovernor() public {
        uint256 balance = angle.balanceOf(address(alice));
        uint256 creatorBalance = angle.balanceOf(address(creator));
        vm.startPrank(alice);
        creator.increaseTokenBalance(address(bob), address(angle), 1e9);
        assertEq(creator.creatorBalance(address(bob), address(angle)), 1e9);
        assertEq(angle.balanceOf(address(alice)), balance - 1e9);
        assertEq(angle.balanceOf(address(creator)), creatorBalance + 1e9);
        vm.expectRevert(Errors.NotAllowed.selector);
        creator.decreaseTokenBalance(address(bob), address(angle), address(alice), 1e9);
        vm.stopPrank();
    }

    function test_RevertWhenNotEnoughBalance() public {
        uint256 balance = angle.balanceOf(address(alice));
        uint256 creatorBalance = angle.balanceOf(address(creator));
        vm.startPrank(alice);
        creator.increaseTokenBalance(address(alice), address(angle), 1e9);
        assertEq(creator.creatorBalance(address(alice), address(angle)), 1e9);
        assertEq(angle.balanceOf(address(alice)), balance - 1e9);
        assertEq(angle.balanceOf(address(creator)), creatorBalance + 1e9);
        vm.expectRevert();
        creator.decreaseTokenBalance(address(alice), address(angle), address(alice), 1e10);
        vm.stopPrank();
    }
}

contract Test_DistributionCreator_adjustTokenAllowance is DistributionCreatorTest {
    function test_SuccessWhenUser() public {
        vm.startPrank(alice);
        creator.increaseTokenAllowance(address(alice), address(bob), address(angle), 1e9);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9);

        creator.increaseTokenAllowance(address(alice), address(bob), address(angle), 1e5);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9 + 1e5);

        creator.increaseTokenAllowance(address(alice), address(dylan), address(angle), 1e10);
        assertEq(creator.creatorAllowance(address(alice), address(dylan), address(angle)), 1e10);

        creator.increaseTokenAllowance(address(alice), address(dylan), address(angle), 1e6);
        assertEq(creator.creatorAllowance(address(alice), address(dylan), address(angle)), 1e10 + 1e6);

        creator.decreaseTokenAllowance(address(alice), address(dylan), address(angle), 1e8);
        assertEq(creator.creatorAllowance(address(alice), address(dylan), address(angle)), 1e10 + 1e6 - 1e8);

        creator.decreaseTokenAllowance(address(alice), address(bob), address(angle), 1e7);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9 + 1e5 - 1e7);

        vm.stopPrank();
    }

    function test_SuccessWhenGovernor() public {
        vm.startPrank(governor);
        creator.increaseTokenAllowance(address(alice), address(bob), address(angle), 1e9);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9);

        creator.increaseTokenAllowance(address(alice), address(bob), address(angle), 1e5);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9 + 1e5);

        creator.increaseTokenAllowance(address(alice), address(dylan), address(angle), 1e10);
        assertEq(creator.creatorAllowance(address(alice), address(dylan), address(angle)), 1e10);

        creator.increaseTokenAllowance(address(alice), address(dylan), address(angle), 1e6);
        assertEq(creator.creatorAllowance(address(alice), address(dylan), address(angle)), 1e10 + 1e6);

        creator.decreaseTokenAllowance(address(alice), address(dylan), address(angle), 1e8);
        assertEq(creator.creatorAllowance(address(alice), address(dylan), address(angle)), 1e10 + 1e6 - 1e8);

        creator.decreaseTokenAllowance(address(alice), address(bob), address(angle), 1e7);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9 + 1e5 - 1e7);
        vm.stopPrank();
    }

    function test_RevertWhenNotUserOrGovernor() public {
        vm.startPrank(bob);
        vm.expectRevert(Errors.NotAllowed.selector);
        creator.increaseTokenAllowance(address(alice), address(bob), address(angle), 1e9);
        vm.stopPrank();
    }

    function test_RevertWhenNotEnoughAllowance() public {
        vm.startPrank(alice);
        creator.increaseTokenAllowance(address(alice), address(bob), address(angle), 1e9);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9);
        vm.expectRevert();
        creator.decreaseTokenAllowance(address(alice), address(bob), address(angle), 1e10);

        vm.expectRevert();
        creator.decreaseTokenAllowance(address(alice), address(dylan), address(angle), 1);

        vm.stopPrank();
    }
}

contract Test_DistributionCreator_toggleCampaignOperator is DistributionCreatorTest {
    function test_SuccessWhenUser() public {
        vm.startPrank(alice);
        creator.toggleCampaignOperator(address(alice), address(bob));
        assertEq(creator.campaignOperators(address(alice), address(bob)), 1);
        creator.toggleCampaignOperator(address(alice), address(bob));
        assertEq(creator.campaignOperators(address(alice), address(bob)), 0);
        creator.toggleCampaignOperator(address(alice), address(dylan));
        assertEq(creator.campaignOperators(address(alice), address(dylan)), 1);

        vm.stopPrank();
    }

    function test_SuccessWhenGovernor() public {
        vm.startPrank(governor);
        creator.toggleCampaignOperator(address(alice), address(bob));
        assertEq(creator.campaignOperators(address(alice), address(bob)), 1);
        creator.toggleCampaignOperator(address(alice), address(bob));
        assertEq(creator.campaignOperators(address(alice), address(bob)), 0);
        creator.toggleCampaignOperator(address(alice), address(dylan));
        assertEq(creator.campaignOperators(address(alice), address(dylan)), 1);
        vm.stopPrank();
    }

    function test_RevertWhenNotUserOrGovernor() public {
        vm.startPrank(bob);
        vm.expectRevert(Errors.NotAllowed.selector);
        creator.toggleCampaignOperator(address(alice), address(bob));
        vm.stopPrank();
    }
}
