// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DistributionParameters, CampaignParameters, RewardTokenAmounts } from "../../../contracts/DistributionCreator.sol";
import "../Fixture.t.sol";

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

        vm.startPrank(guardian);
        creator.toggleSigningWhitelist(alice);

        vm.startPrank(governor);
        creator.toggleTokenWhitelist(address(agEUR));
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
    DistributionCreator d;

    function setUp() public override {
        super.setUp();
        d = DistributionCreator(deployUUPS(address(new DistributionCreator()), hex""));
    }

    function test_RevertWhen_CalledOnImplem() public {
        vm.expectRevert("Initializable: contract is already initialized");
        creatorImpl.initialize(ICore(address(0)), address(bob), 1e8);
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        d.initialize(ICore(address(0)), address(bob), 1e8);

        vm.expectRevert(ZeroAddress.selector);
        d.initialize(ICore(address(coreBorrow)), address(0), 1e8);
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(InvalidParam.selector);
        d.initialize(ICore(address(coreBorrow)), address(bob), 1e9);
    }

    function test_Success() public {
        d.initialize(ICore(address(coreBorrow)), address(bob), 1e8);

        assertEq(address(d.distributor()), address(bob));
        assertEq(address(d.core()), address(coreBorrow));
        assertEq(d.defaultFees(), 1e8);
    }
}

contract Test_DistributionCreator_CreateDistribution is DistributionCreatorTest {
    function test_RevertWhen_CampaignSouldStartInFuture() public {
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
            epochStart: uint32(block.timestamp - 1),
            numEpoch: 25,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });
        vm.expectRevert(CampaignSouldStartInFuture.selector);
        creator.createDistribution(distribution);
    }

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
        vm.expectRevert(CampaignDurationBelowHour.selector);

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
        vm.expectRevert(CampaignRewardTokenNotWhitelisted.selector);

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
        vm.expectRevert(CampaignRewardTooLow.selector);

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
        uint256 distributionAmount = creator.createDistribution(distribution);

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
        assertEq(distributionAmount, fetchedCampaign.amount * 10 / 9);

        (CampaignParameters[] memory campaigns,) = creator.getCampaignsBetween(uint32(block.timestamp) + 2, uint32(block.timestamp) + 2 + distribution.numEpoch * 3600, 0, type(uint32).max);
        assertEq(1, campaigns.length);
        assertEq(campaignId, campaigns[0].campaignId);
    }
}

contract Test_DistributionCreator_CreateDistributions is DistributionCreatorTest {
    function test_RevertWhen_CampaignAlreadyExists() public {
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
            numEpoch: 25,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });
        vm.expectRevert(CampaignAlreadyExists.selector);

        DistributionParameters[] memory distributions = new DistributionParameters[](2);
        distributions[0] = distribution;
        distributions[1] = distribution;
        vm.prank(alice);
        creator.createDistributions(distributions);
    }

    function test_Success() public {
        DistributionParameters[] memory distributions = new DistributionParameters[](2);
        distributions[0] = DistributionParameters({
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
            numEpoch: 25,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });
        distributions[1] = DistributionParameters({
            uniV3Pool: address(pool),
            rewardToken: address(angle),
            positionWrappers: positionWrappers,
            wrapperTypes: wrapperTypes,
            amount: 2e10,
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
        uint256[] memory distributionAmounts = creator.createDistributions(distributions);

        (CampaignParameters[] memory campaigns,) = creator.getCampaignsBetween(uint32(block.timestamp) + 1, uint32(block.timestamp) + 2 + distributions[0].numEpoch * 3600, 0, type(uint32).max);
        assertEq(2, campaigns.length);
        assertEq(2, distributionAmounts.length);
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
        assertEq(campaignId, campaigns[0].campaignId);
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
        assertEq(campaignId, campaigns[1].campaignId);
        assertEq(uint256(1e10) * 9 / 10, distributionAmounts[0]);
        assertEq(uint256(2e10) * 9 / 10, distributionAmounts[1]);
    }
}

contract Test_DistributionCreator_CreateCampaign is DistributionCreatorTest {
    function test_RevertWhen_CampaignSouldStartInFuture() public {
        CampaignParameters memory campaign = CampaignParameters({
            campaignId: keccak256("TEST"),
            creator: address(0),
            campaignData: hex"ab",
            rewardToken: address(angle),
            amount: 1e10,
            campaignType: 0,
            startTimestamp: uint32(block.timestamp - 1),
            duration: 3600
        });
        vm.expectRevert(CampaignSouldStartInFuture.selector);
        creator.createCampaign(campaign);
    }

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
        vm.expectRevert(CampaignDurationBelowHour.selector);

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
        vm.expectRevert(CampaignRewardTokenNotWhitelisted.selector);

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
        vm.expectRevert(CampaignRewardTooLow.selector);

        vm.prank(alice);
        creator.createCampaign(campaign);
    }

    function test_Success() public {
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
        creator.createCampaign(campaign);

        address[] memory whitelist = new address[](1);
        whitelist[0] = alice;
        address[] memory blacklist = new address[](1);
        blacklist[0] = charlie;

        bytes memory extraData = hex"ab";

        // Additional asserts to check for correct behavior
        (CampaignParameters[] memory campaigns,) = creator.getCampaignsBetween(uint32(block.timestamp) + 1, uint32(block.timestamp) + 1 + campaign.duration, 0, type(uint32).max);
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
        assertEq(campaigns.length, 1);
        assertEq(campaignId, campaigns[0].campaignId);
        assertEq(alice, fetchedCreator);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
        assertEq(campaign.amount, fetchedAmount * 10 / 9);
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

        vm.expectRevert(CampaignAlreadyExists.selector);

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
        bytes32[] memory campaignIds = creator.createCampaigns(campaigns);

        // Additional asserts to check for correct behavior
        (CampaignParameters[] memory fetchedCampaigns,) = creator.getCampaignsBetween(uint32(block.timestamp) + 1, uint32(block.timestamp) + 2 + campaigns[0].duration, 0, type(uint32).max);
        assertEq(fetchedCampaigns.length, 2);
        {
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
        assertEq(campaignId, fetchedCampaigns[0].campaignId);
        assertEq(campaignIds[0], campaignId);
        assertEq(alice, fetchedCreator);
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaigns[0].campaignType, fetchedCampaignType);
        assertEq(campaigns[0].startTimestamp, fetchedStartTimestamp);
        assertEq(campaigns[0].duration, fetchedDuration);
        assertEq(campaigns[0].campaignData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
        assertEq(campaigns[0].amount, fetchedAmount * 10 / 9);
        }

        // Additional asserts to check for correct behavior
        {
        bytes32 campaignId = bytes32(
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
            bytes32 fetchedCampaignId,
            address fetchedCreator,
            address fetchedRewardToken,
            uint256 fetchedAmount,
            uint32 fetchedCampaignType,
            uint32 fetchedStartTimestamp,
            uint32 fetchedDuration,
            bytes memory fetchedCampaignData
        ) = creator.campaignList(creator.campaignLookup(campaignId));
            assertEq(campaignId, fetchedCampaigns[1].campaignId);
            assertEq(campaignIds[1], campaignId);
            assertEq(alice, fetchedCreator);
            assertEq(address(angle), fetchedRewardToken);
            assertEq(campaigns[1].campaignType, fetchedCampaignType);
            assertEq(campaigns[1].startTimestamp, fetchedStartTimestamp);
            assertEq(campaigns[1].duration, fetchedDuration);
            assertEq(campaigns[1].campaignData, fetchedCampaignData);
            assertEq(campaignId, fetchedCampaignId);
            assertEq(campaigns[1].amount, fetchedAmount * 10 / 9);
        }
    }
}

contract Test_DistributionCreator_setCampaignFees is DistributionCreatorTest {
    event CampaignSpecificFeesSet(uint32 campaignType, uint256 _fees);

    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.expectRevert(NotGovernorOrGuardian.selector);
        vm.prank(alice);
        creator.setCampaignFees(0, 1e8);
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(InvalidParam.selector);
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

contract Test_DistributionCreator_sign is DistributionCreatorTest {
    function test_Success() public {
        vm.prank(governor);
        creator.setMessage("test");

        assertEq("test", creator.message());
        assertEq(creator.userSignatures(alice), bytes32(0));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, creator.messageHash());
        vm.prank(alice);
        creator.sign(abi.encodePacked(r, s, v));

        assertEq(creator.userSignatures(alice), creator.messageHash());
    }

    function test_RevertWith_InvalidSignature() public {
        vm.prank(governor);
        creator.setMessage("test");

        assertEq("test", creator.message());
        assertEq(creator.userSignatures(alice), bytes32(0));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, creator.messageHash());
        vm.prank(alice);
        vm.expectRevert(InvalidSignature.selector);
        creator.sign(abi.encodePacked(r, s, v));
    }
}

contract Test_DistributionCreator_acceptConditions is DistributionCreatorTest {
    function test_Success() public {
        assertEq(creator.userSignatureWhitelist(bob), 0);

        vm.prank(bob);
        creator.acceptConditions();

        assertEq(creator.userSignatureWhitelist(bob), 1);
    }
}

contract Test_DistributionCreator_setFees is DistributionCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(NotGovernor.selector);
        vm.prank(alice);
        creator.setFees(1e8);
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(InvalidParam.selector);
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
        vm.expectRevert(NotGovernor.selector);
        vm.prank(alice);
        creator.setNewDistributor(address(bob));
    }

    function test_RevertWhen_InvalidParam() public {
        vm.expectRevert(InvalidParam.selector);
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
        vm.expectRevert(NotGovernorOrGuardian.selector);
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
        vm.expectRevert(NotGovernor.selector);
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

        vm.expectRevert(NotGovernor.selector);
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
    function test_Success() public {
        RewardTokenAmounts[] memory tokens = creator.getValidRewardTokens();

        assertEq(tokens.length, 1);
        assertEq(tokens[0].token, address(angle));
        assertEq(tokens[0].minimumAmountPerEpoch, 1e8);
    }

    function test_SuccessSkip() public {
        (RewardTokenAmounts[] memory tokens, uint256 i) = creator.getValidRewardTokens(1, 0);

        assertEq(tokens.length, 0);
        assertEq(i, 1);
    }
}

contract Test_DistributionCreator_signAndCreateCampaign is DistributionCreatorTest {
    function test_Success() public {
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

        {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, creator.messageHash());

        vm.startPrank(bob);

        angle.approve(address(creator), 1e8);
        creator.signAndCreateCampaign(campaign, abi.encodePacked(r, s, v));

        vm.stopPrank();
        }

        address[] memory whitelist = new address[](1);
        whitelist[0] = bob;
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
        assertEq(address(angle), fetchedRewardToken);
        assertEq(campaign.campaignType, fetchedCampaignType);
        assertEq(campaign.startTimestamp, fetchedStartTimestamp);
        assertEq(campaign.duration, fetchedDuration);
        assertEq(extraData, fetchedCampaignData);
        assertEq(campaignId, fetchedCampaignId);
        assertEq(campaign.amount, fetchedAmount * 10 / 9);
    }

    function test_InvalidSignature() public {
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

        {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, creator.messageHash());

        vm.startPrank(bob);

        angle.approve(address(creator), 1e8);
        vm.expectRevert(InvalidSignature.selector);
        creator.signAndCreateCampaign(campaign, abi.encodePacked(r, s, v));

        vm.stopPrank();
        }
    }
}
