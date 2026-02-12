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
        vm.expectRevert(Errors.CampaignDurationNull.selector);

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
        vm.expectRevert(Errors.CampaignDurationNull.selector);

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
    event ConditionsAccepted(address indexed user, bytes32 conditionsHash);

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

    function test_Success_EmitsConditionsAcceptedEvent() public {
        // Set a message
        string memory message = "I accept the terms and conditions";
        vm.prank(governor);
        creator.setMessage(message);

        bytes32 expectedHash = ECDSA.toEthSignedMessageHash(bytes(message));

        // Expect the event
        vm.expectEmit(true, false, false, true);
        emit ConditionsAccepted(alice, expectedHash);

        // Accept conditions as alice
        vm.prank(alice);
        creator.acceptConditions();
    }

    function test_Success_EmitsEventWithZeroHash() public {
        // When no message is set, event should emit with zero hash
        assertEq(creator.messageHash(), bytes32(0));

        vm.expectEmit(true, false, false, true);
        emit ConditionsAccepted(alice, bytes32(0));

        vm.prank(alice);
        creator.acceptConditions();
    }

    function test_Success_MultipleUsersCanAccept() public {
        string memory message = "Terms v1";
        vm.prank(governor);
        creator.setMessage(message);

        bytes32 expectedHash = ECDSA.toEthSignedMessageHash(bytes(message));

        // Multiple users accept
        vm.prank(alice);
        creator.acceptConditions();

        vm.prank(bob);
        creator.acceptConditions();

        vm.prank(charlie);
        creator.acceptConditions();

        // Verify all signatures
        assertEq(creator.userSignatures(alice), expectedHash);
        assertEq(creator.userSignatures(bob), expectedHash);
        assertEq(creator.userSignatures(charlie), expectedHash);
    }

    function test_Success_UserMustReacceptAfterMessageChange() public {
        // Set initial message
        string memory message1 = "Terms v1";
        vm.prank(governor);
        creator.setMessage(message1);

        bytes32 hash1 = ECDSA.toEthSignedMessageHash(bytes(message1));

        // Alice accepts
        vm.prank(alice);
        creator.acceptConditions();
        assertEq(creator.userSignatures(alice), hash1);

        // Governor changes the message
        string memory message2 = "Terms v2";
        vm.prank(governor);
        creator.setMessage(message2);

        bytes32 hash2 = ECDSA.toEthSignedMessageHash(bytes(message2));

        // Alice's signature is now outdated (doesn't match current messageHash)
        assertEq(creator.userSignatures(alice), hash1);
        assertEq(creator.messageHash(), hash2);
        assertTrue(creator.userSignatures(alice) != creator.messageHash());

        // Alice accepts new conditions
        vm.prank(alice);
        creator.acceptConditions();

        // Now signature matches
        assertEq(creator.userSignatures(alice), hash2);
        assertEq(creator.userSignatures(alice), creator.messageHash());
    }

    function test_Success_AcceptConditionsUpdatesExistingSignature() public {
        // Set message and accept
        string memory message1 = "Terms v1";
        vm.prank(governor);
        creator.setMessage(message1);

        bytes32 hash1 = ECDSA.toEthSignedMessageHash(bytes(message1));

        vm.prank(alice);
        creator.acceptConditions();
        assertEq(creator.userSignatures(alice), hash1);

        // Change message
        string memory message2 = "Terms v2";
        vm.prank(governor);
        creator.setMessage(message2);

        bytes32 hash2 = ECDSA.toEthSignedMessageHash(bytes(message2));

        // Expect event with new hash
        vm.expectEmit(true, false, false, true);
        emit ConditionsAccepted(alice, hash2);

        // Accept again - should update signature
        vm.prank(alice);
        creator.acceptConditions();

        assertEq(creator.userSignatures(alice), hash2);
    }
}

contract Test_DistributionCreator_getLatestCampaignParams is DistributionCreatorTest {
    bytes32 testCampaignId;
    uint256 originalAmount;
    uint32 originalStartTimestamp;
    uint32 originalDuration;
    uint32 originalCampaignType;
    bytes originalCampaignData;

    function setUp() public override {
        super.setUp();

        // Create a campaign
        originalAmount = 100 ether;
        originalStartTimestamp = uint32(block.timestamp + 600);
        originalDuration = 3600 * 24;
        originalCampaignType = 1;
        originalCampaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        vm.prank(alice);
        testCampaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: originalCampaignType,
                startTimestamp: originalStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );
    }

    function test_Success_ReturnsOriginalWhenNoOverride() public {
        // Get latest params - should be original since no override exists
        CampaignParameters memory params = creator.getLatestCampaignParams(testCampaignId);

        // Verify it returns the original campaign data
        assertEq(params.campaignId, testCampaignId);
        assertEq(params.creator, alice);
        assertEq(params.rewardToken, address(angle));
        // Amount is after fees (90% of original due to 10% default fee)
        uint256 expectedAmountAfterFees = (originalAmount * (1e9 - creator.defaultFees())) / 1e9;
        assertEq(params.amount, expectedAmountAfterFees);
        assertEq(params.campaignType, originalCampaignType);
        assertEq(params.startTimestamp, originalStartTimestamp);
        assertEq(params.duration, originalDuration);
    }

    function test_Success_ReturnsOverrideWhenOverrideExists() public {
        // Create an override with different campaignType, startTimestamp, and duration
        uint32 newCampaignType = 5;
        uint32 newStartTimestamp = originalStartTimestamp + 1000;
        uint32 newDuration = 3600 * 12; // 12 hours instead of 24
        bytes memory newCampaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            new address[](0),
            new address[](0),
            hex""
        );

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount, // This will be preserved anyway
                campaignType: newCampaignType,
                startTimestamp: newStartTimestamp,
                duration: newDuration,
                campaignData: newCampaignData
            })
        );

        // Get latest params - should return override
        CampaignParameters memory params = creator.getLatestCampaignParams(testCampaignId);

        // Verify it returns the overridden values
        assertEq(params.campaignId, testCampaignId);
        assertEq(params.creator, alice); // Preserved from original
        assertEq(params.rewardToken, address(angle)); // Preserved from original
        // Amount is preserved from original (after fees)
        uint256 expectedAmountAfterFees = (originalAmount * (1e9 - creator.defaultFees())) / 1e9;
        assertEq(params.amount, expectedAmountAfterFees);
        // These are the overridden values
        assertEq(params.campaignType, newCampaignType);
        assertEq(params.startTimestamp, newStartTimestamp);
        assertEq(params.duration, newDuration);
        assertEq(params.campaignData, newCampaignData);
    }

    function test_Success_OriginalCampaignUnchangedAfterOverride() public {
        // Get original campaign
        CampaignParameters memory originalParams = creator.campaign(testCampaignId);

        // Create an override
        uint32 newCampaignType = 5;
        uint32 newStartTimestamp = originalStartTimestamp + 1000;

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: newCampaignType,
                startTimestamp: newStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );

        // Verify campaign() still returns original (unchanged)
        CampaignParameters memory stillOriginal = creator.campaign(testCampaignId);
        assertEq(stillOriginal.campaignType, originalParams.campaignType);
        assertEq(stillOriginal.startTimestamp, originalParams.startTimestamp);

        // But getLatestCampaignParams returns override
        CampaignParameters memory latest = creator.getLatestCampaignParams(testCampaignId);
        assertEq(latest.campaignType, newCampaignType);
        assertEq(latest.startTimestamp, newStartTimestamp);
    }

    function test_Success_MultipleOverridesReturnsLatest() public {
        // First override
        uint32 firstOverrideCampaignType = 2;
        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: firstOverrideCampaignType,
                startTimestamp: originalStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );

        // Verify first override
        CampaignParameters memory afterFirst = creator.getLatestCampaignParams(testCampaignId);
        assertEq(afterFirst.campaignType, firstOverrideCampaignType);

        // Second override
        uint32 secondOverrideCampaignType = 7;
        uint32 newDuration = 3600 * 6; // 6 hours

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: secondOverrideCampaignType,
                startTimestamp: originalStartTimestamp,
                duration: newDuration,
                campaignData: originalCampaignData
            })
        );

        // Verify second override is returned (latest)
        CampaignParameters memory afterSecond = creator.getLatestCampaignParams(testCampaignId);
        assertEq(afterSecond.campaignType, secondOverrideCampaignType);
        assertEq(afterSecond.duration, newDuration);
    }

    function test_Success_ReturnsCorrectDataForDifferentCampaigns() public {
        // Create a second campaign
        uint32 secondCampaignStartTimestamp = uint32(block.timestamp + 1200);
        uint32 secondCampaignDuration = 3600 * 48;
        uint32 secondCampaignType = 3;

        vm.prank(alice);
        bytes32 secondCampaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: 50 ether,
                campaignType: secondCampaignType,
                startTimestamp: secondCampaignStartTimestamp,
                duration: secondCampaignDuration,
                campaignData: originalCampaignData
            })
        );

        // Override only the first campaign
        uint32 overriddenCampaignType = 9;
        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: overriddenCampaignType,
                startTimestamp: originalStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );

        // First campaign should return override
        CampaignParameters memory firstLatest = creator.getLatestCampaignParams(testCampaignId);
        assertEq(firstLatest.campaignType, overriddenCampaignType);

        // Second campaign should return original (no override)
        CampaignParameters memory secondLatest = creator.getLatestCampaignParams(secondCampaignId);
        assertEq(secondLatest.campaignType, secondCampaignType);
        assertEq(secondLatest.startTimestamp, secondCampaignStartTimestamp);
        assertEq(secondLatest.duration, secondCampaignDuration);
    }

    function test_Success_PreservesImmutableFieldsInOverride() public {
        // Try to override with different creator, rewardToken, and amount
        // These should be preserved from original
        address fakeCreator = address(0xdead);
        address fakeToken = address(0xbeef);
        uint256 fakeAmount = 999 ether;

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: fakeCreator, // Should be ignored
                rewardToken: fakeToken, // Should be ignored
                amount: fakeAmount, // Should be ignored
                campaignType: 5,
                startTimestamp: originalStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );

        CampaignParameters memory params = creator.getLatestCampaignParams(testCampaignId);

        // Immutable fields should be preserved
        assertEq(params.creator, alice);
        assertEq(params.rewardToken, address(angle));
        uint256 expectedAmountAfterFees = (originalAmount * (1e9 - creator.defaultFees())) / 1e9;
        assertEq(params.amount, expectedAmountAfterFees);

        // Mutable field should be overridden
        assertEq(params.campaignType, 5);
    }
}

contract Test_DistributionCreator_getCampaignListReallocationAt is DistributionCreatorTest {
    bytes32 testCampaignId;
    uint256 originalAmount;
    uint32 originalStartTimestamp;
    uint32 originalDuration;
    bytes originalCampaignData;

    function setUp() public override {
        super.setUp();

        // Create a campaign
        originalAmount = 100 ether;
        originalStartTimestamp = uint32(block.timestamp + 600);
        originalDuration = 3600 * 24;
        originalCampaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        vm.prank(alice);
        testCampaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );
    }

    function test_Success_ReturnsEmptyWhenNoReallocation() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        // Get the full reallocation list - should be empty
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, 0);
    }

    function test_Success_ReturnsSingleReallocation() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);
        address to = address(0x2222);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, to);

        // Verify using getCampaignListReallocationAt
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 0), froms[0]);

        // Verify using getCampaignListReallocation
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, 1);
        assertEq(list[0], froms[0]);
    }

    function test_Success_ReturnsMultipleReallocationsInOrder() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address[] memory froms = new address[](3);
        froms[0] = address(0x1111);
        froms[1] = address(0x2222);
        froms[2] = address(0x3333);
        address to = address(0x4444);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, to);

        // Verify each index returns correct address
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 0), froms[0]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 1), froms[1]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 2), froms[2]);

        // Verify full list
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, 3);
        assertEq(list[0], froms[0]);
        assertEq(list[1], froms[1]);
        assertEq(list[2], froms[2]);
    }

    function test_Success_MultipleReallocationCallsAccumulate() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        // First reallocation call
        address[] memory froms1 = new address[](2);
        froms1[0] = address(0x1111);
        froms1[1] = address(0x2222);
        address to1 = address(0xAAAA);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms1, to1);

        // Second reallocation call with different addresses
        address[] memory froms2 = new address[](2);
        froms2[0] = address(0x3333);
        froms2[1] = address(0x4444);
        address to2 = address(0xBBBB);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms2, to2);

        // Verify all 4 addresses are in the list in order
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 0), froms1[0]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 1), froms1[1]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 2), froms2[0]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 3), froms2[1]);

        // Verify full list length
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, 4);
    }

    function test_Success_DifferentCampaignsHaveSeparateLists() public {
        // Create a second campaign
        vm.prank(alice);
        bytes32 secondCampaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: 50 ether,
                campaignType: 2,
                startTimestamp: originalStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after both campaigns end
        vm.warp(originalStartTimestamp + originalDuration + 1);

        // Reallocate for first campaign
        address[] memory froms1 = new address[](2);
        froms1[0] = address(0x1111);
        froms1[1] = address(0x2222);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms1, address(0xAAAA));

        // Reallocate for second campaign with different addresses
        address[] memory froms2 = new address[](1);
        froms2[0] = address(0x5555);

        vm.prank(alice);
        creator.reallocateCampaignRewards(secondCampaignId, froms2, address(0xBBBB));

        // Verify first campaign has its own list
        address[] memory list1 = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list1.length, 2);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 0), froms1[0]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 1), froms1[1]);

        // Verify second campaign has its own separate list
        address[] memory list2 = creator.getCampaignListReallocation(secondCampaignId);
        assertEq(list2.length, 1);
        assertEq(creator.getCampaignListReallocationAt(secondCampaignId, 0), froms2[0]);
    }

    function test_Success_ReallocationToSameRecipientMultipleTimes() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address to = address(0xAAAA);

        // Multiple calls reallocating to the same recipient
        address[] memory froms1 = new address[](1);
        froms1[0] = address(0x1111);

        address[] memory froms2 = new address[](1);
        froms2[0] = address(0x2222);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms1, to);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms2, to);

        // Verify both source addresses are in the list
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 0), froms1[0]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 1), froms2[0]);

        // Verify the reallocation mapping points to the same recipient
        assertEq(creator.campaignReallocation(testCampaignId, froms1[0]), to);
        assertEq(creator.campaignReallocation(testCampaignId, froms2[0]), to);
    }

    function test_Success_ReallocationToDifferentRecipients() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        // Reallocate different addresses to different recipients
        address[] memory froms1 = new address[](1);
        froms1[0] = address(0x1111);
        address to1 = address(0xAAAA);

        address[] memory froms2 = new address[](1);
        froms2[0] = address(0x2222);
        address to2 = address(0xBBBB);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms1, to1);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms2, to2);

        // Verify list contains both source addresses
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, 2);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 0), froms1[0]);
        assertEq(creator.getCampaignListReallocationAt(testCampaignId, 1), froms2[0]);

        // Verify each source maps to correct recipient
        assertEq(creator.campaignReallocation(testCampaignId, froms1[0]), to1);
        assertEq(creator.campaignReallocation(testCampaignId, froms2[0]), to2);
    }

    function test_RevertWhen_CampaignNotEnded() public {
        // Don't warp - campaign hasn't ended yet
        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        vm.expectRevert(Errors.InvalidReallocation.selector);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));
    }

    function test_RevertWhen_NotCreatorOrOperator() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        // Bob is not the creator or an operator
        vm.prank(bob);
        vm.expectRevert(Errors.OperatorNotAllowed.selector);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));
    }

    function test_RevertWhen_ToAddressIsZero() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        vm.expectRevert(Errors.ZeroAddress.selector);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0));
    }

    function test_Success_UsesOverriddenDurationForEndTimeCheck() public {
        // Original campaign: startTimestamp + 24 hours duration
        // We'll override to have a shorter duration (12 hours)
        uint32 shorterDuration = 3600 * 12; // 12 hours

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: shorterDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after the OVERRIDDEN end time (12 hours) but before ORIGINAL end time (24 hours)
        vm.warp(originalStartTimestamp + shorterDuration + 1);

        // This should SUCCEED because reallocation uses overridden duration
        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));

        // Verify reallocation was successful
        assertEq(creator.campaignReallocation(testCampaignId, froms[0]), address(0x2222));
    }

    function test_RevertWhen_OverriddenDurationNotYetEnded() public {
        // Original campaign: startTimestamp + 24 hours duration
        // We'll override to have a LONGER duration (48 hours)
        uint32 longerDuration = 3600 * 48; // 48 hours

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: longerDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after the ORIGINAL end time (24 hours) but before OVERRIDDEN end time (48 hours)
        vm.warp(originalStartTimestamp + originalDuration + 1);

        // This should FAIL because reallocation uses overridden duration (48 hours)
        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        vm.expectRevert(Errors.InvalidReallocation.selector);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));
    }

    function test_Success_UsesOverriddenStartTimestampForEndTimeCheck() public {
        // Override with a later start timestamp
        uint32 laterStartTimestamp = originalStartTimestamp + 3600; // 1 hour later

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: laterStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after the OVERRIDDEN end time (laterStart + 24h)
        vm.warp(laterStartTimestamp + originalDuration + 1);

        // This should SUCCEED
        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));

        assertEq(creator.campaignReallocation(testCampaignId, froms[0]), address(0x2222));
    }

    function test_RevertWhen_OverriddenStartTimestampNotYetEnded() public {
        // Override with a later start timestamp
        uint32 laterStartTimestamp = originalStartTimestamp + 3600 * 12; // 12 hours later

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: laterStartTimestamp,
                duration: originalDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after ORIGINAL end time but before OVERRIDDEN end time
        // Original ends at: originalStartTimestamp + 24h
        // Overridden ends at: (originalStartTimestamp + 12h) + 24h = originalStartTimestamp + 36h
        vm.warp(originalStartTimestamp + originalDuration + 1);

        // This should FAIL because we're before the overridden end time
        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        vm.expectRevert(Errors.InvalidReallocation.selector);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));
    }

    function test_Success_UsesOverriddenBothStartAndDuration() public {
        // Override with both different start and duration
        uint32 newStartTimestamp = originalStartTimestamp + 3600; // 1 hour later
        uint32 newDuration = 3600 * 6; // 6 hours (shorter)

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: newStartTimestamp,
                duration: newDuration,
                campaignData: originalCampaignData
            })
        );

        // Overridden end time: newStartTimestamp + 6h = originalStartTimestamp + 7h
        // Original end time: originalStartTimestamp + 24h
        // Warp to after overridden end but before original end
        vm.warp(newStartTimestamp + newDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));

        assertEq(creator.campaignReallocation(testCampaignId, froms[0]), address(0x2222));
    }

    function test_Success_MultipleOverridesUsesLatestForTimestampCheck() public {
        // First override: shorter duration (12 hours)
        uint32 firstDuration = 3600 * 12;

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: firstDuration,
                campaignData: originalCampaignData
            })
        );

        // Second override: even shorter duration (6 hours)
        uint32 secondDuration = 3600 * 6;

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: secondDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after the LATEST (second) override end time
        vm.warp(originalStartTimestamp + secondDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));

        assertEq(creator.campaignReallocation(testCampaignId, froms[0]), address(0x2222));
    }

    function test_Success_OperatorCanReallocateAfterOverriddenEnd() public {
        // Set bob as operator for alice
        vm.prank(alice);
        creator.toggleCampaignOperator(alice, bob);

        // Override with shorter duration
        uint32 shorterDuration = 3600 * 12;

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: shorterDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after overridden end time
        vm.warp(originalStartTimestamp + shorterDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        // Bob (operator) can reallocate
        vm.prank(bob);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));

        assertEq(creator.campaignReallocation(testCampaignId, froms[0]), address(0x2222));
    }

    function test_RevertWhen_GovernorNotOperator() public {
        // Override with shorter duration
        uint32 shorterDuration = 3600 * 12;

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: shorterDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after overridden end time
        vm.warp(originalStartTimestamp + shorterDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        // Governor CANNOT reallocate unless they are set as an operator
        // (reallocateCampaignRewards requires creator or operator, not governor)
        vm.prank(governor);
        vm.expectRevert(Errors.OperatorNotAllowed.selector);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));
    }

    function test_RevertWhen_OperatorTriesBeforeOverriddenEnd() public {
        // Set bob as operator for alice
        vm.prank(alice);
        creator.toggleCampaignOperator(alice, bob);

        // Override with longer duration
        uint32 longerDuration = 3600 * 48;

        vm.prank(alice);
        creator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: originalAmount,
                campaignType: 1,
                startTimestamp: originalStartTimestamp,
                duration: longerDuration,
                campaignData: originalCampaignData
            })
        );

        // Warp to after original end but before overridden end
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        // Bob (operator) cannot reallocate - campaign not ended per override
        vm.prank(bob);
        vm.expectRevert(Errors.InvalidReallocation.selector);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));
    }

    function test_Success_ReallocateSameAddressOverwritesPreviousRecipient() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address[] memory froms = new address[](1);
        froms[0] = address(0x1111);

        // First reallocation to recipient A
        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0xAAAA));
        assertEq(creator.campaignReallocation(testCampaignId, froms[0]), address(0xAAAA));

        // Second reallocation of same address to recipient B
        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0xBBBB));

        // Should overwrite to new recipient
        assertEq(creator.campaignReallocation(testCampaignId, froms[0]), address(0xBBBB));

        // But the list should have the address twice (it just pushes)
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, 2);
        assertEq(list[0], froms[0]);
        assertEq(list[1], froms[0]);
    }

    function test_Success_EmptyFromsArrayDoesNothing() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        address[] memory froms = new address[](0);

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));

        // List should still be empty
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, 0);
    }

    function test_Success_LargeNumberOfReallocations() public {
        // Warp to after campaign ends
        vm.warp(originalStartTimestamp + originalDuration + 1);

        uint256 numAddresses = 50;
        address[] memory froms = new address[](numAddresses);
        for (uint256 i = 0; i < numAddresses; i++) {
            froms[i] = address(uint160(0x1000 + i));
        }

        vm.prank(alice);
        creator.reallocateCampaignRewards(testCampaignId, froms, address(0x2222));

        // Verify all addresses are in the list
        address[] memory list = creator.getCampaignListReallocation(testCampaignId);
        assertEq(list.length, numAddresses);

        // Verify each address via getCampaignListReallocationAt
        for (uint256 i = 0; i < numAddresses; i++) {
            assertEq(creator.getCampaignListReallocationAt(testCampaignId, i), froms[i]);
            assertEq(creator.campaignReallocation(testCampaignId, froms[i]), address(0x2222));
        }
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

contract Test_DistributionCreator_recover is DistributionCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        vm.prank(alice);
        creator.recover(address(angle), address(bob), 10);
    }

    function test_Success() public {
        uint256 balance = angle.balanceOf(address(bob));

        vm.prank(governor);
        creator.recover(address(angle), address(bob), 11e9);

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

        creator.recover(address(angle), address(bob), angle.balanceOf(address(creator)));
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

    function test_RevertWhenUserAddressIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.ZeroAddress.selector);
        creator.increaseTokenBalance(address(0), address(angle), 1e9);
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

    function test_DecreaseAllowanceClampsToZero() public {
        vm.startPrank(alice);
        creator.increaseTokenAllowance(address(alice), address(bob), address(angle), 1e9);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 1e9);

        // Decreasing by more than current allowance should clamp to 0 (not revert)
        creator.decreaseTokenAllowance(address(alice), address(bob), address(angle), 1e10);
        assertEq(creator.creatorAllowance(address(alice), address(bob), address(angle)), 0);

        // Decreasing from 0 should stay at 0 (not revert)
        creator.decreaseTokenAllowance(address(alice), address(dylan), address(angle), 1);
        assertEq(creator.creatorAllowance(address(alice), address(dylan), address(angle)), 0);

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
