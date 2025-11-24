// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { DistributionCreator, DistributionParameters, CampaignParameters } from "../contracts/DistributionCreator.sol";
import { Distributor, MerkleTree } from "../contracts/Distributor.sol";
import { Fixture, IERC20 } from "./Fixture.t.sol";
import { Errors } from "../contracts/utils/Errors.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DistributionCreatorCreateCampaignTest is Fixture {
    using SafeERC20 for IERC20;

    uint256 constant maxDistribForOOG = 1e4;
    uint256 constant nbrDistrib = 10;
    uint32 initStartTime;
    uint32 initEndTime;
    uint32 startTime;
    uint32 endTime;
    uint32 numEpoch;

    function setUp() public override {
        super.setUp();

        initStartTime = uint32(block.timestamp);
        numEpoch = 25;
        initEndTime = startTime + numEpoch * EPOCH_DURATION;

        vm.prank(governor);
        creator.setFeeRecipient(dylan);

        vm.startPrank(guardian);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(angle);
        amounts[0] = 1e8;
        creator.setRewardTokenMinAmounts(tokens, amounts);
        vm.stopPrank();

        angle.mint(address(alice), 1e22);
        vm.prank(alice);
        angle.approve(address(creator), type(uint256).max);

        vm.stopPrank();
    }

    function testUnit_CreateCampaignWithDefaultFees() public {
        IERC20 rewardToken = IERC20(address(angle));
        uint256 amount = 100 ether;
        uint256 amountAfterFees = 90 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        CampaignParameters memory campaign = creator.campaign(campaignId);
        assertEq(campaign.creator, alice);
        assertEq(campaign.rewardToken, address(rewardToken));
        assertEq(campaign.amount, (amount * (1e9 - creator.defaultFees())) / 1e9);
        assertEq(campaign.campaignType, 1);
        assertEq(campaign.startTimestamp, startTimestamp);
        assertEq(campaign.duration, 3600 * 24);
    }

    function testUnit_CreateCampaignWithSetFees() public {
        uint32 campaignType = 1;
        vm.prank(guardian);
        creator.setCampaignFees(campaignType, 1e7);

        IERC20 rewardToken = IERC20(address(angle));
        uint256 amount = 100 ether;
        uint256 amountAfterFees = 90 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);

        uint256 prevBalance = rewardToken.balanceOf(alice);

        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: campaignType,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        CampaignParameters memory campaign = creator.campaign(campaignId);
        assertEq(campaign.creator, alice);
        assertEq(campaign.rewardToken, address(rewardToken));
        assertEq(campaign.amount, (amount * (1e9 - 1e7)) / 1e9);
        assertEq(campaign.campaignType, 1);
        assertEq(campaign.startTimestamp, startTimestamp);
        assertEq(campaign.duration, 3600 * 24);
        assertEq(rewardToken.balanceOf(alice), prevBalance - amount);
        assertEq(rewardToken.balanceOf(dylan), (amount * 1e7) / 1e9);
    }
}

contract DistributionCreatorCreateReallocationTest is Fixture {
    using SafeERC20 for IERC20;

    Distributor public distributor;
    Distributor public distributorImpl;
    uint32 initStartTime;
    uint32 initEndTime;
    uint32 startTime;
    uint32 endTime;
    uint32 numEpoch;

    function setUp() public override {
        super.setUp();

        distributorImpl = new Distributor();
        distributor = Distributor(deployUUPS(address(distributorImpl), hex""));
        distributor.initialize(IAccessControlManager(address(accessControlManager)));

        vm.startPrank(governor);
        distributor.setDisputeAmount(1e18);
        distributor.setDisputePeriod(1 days);
        distributor.setDisputeToken(angle);
        vm.stopPrank();

        initStartTime = uint32(block.timestamp);
        numEpoch = 25;
        initEndTime = startTime + numEpoch * EPOCH_DURATION;

        vm.startPrank(governor);
        creator.setNewDistributor(address(distributor));
        creator.setFeeRecipient(dylan);
        vm.stopPrank();

        vm.startPrank(guardian);
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        tokens[0] = address(angle);
        amounts[0] = 1e8;
        tokens[1] = address(agEUR);
        amounts[1] = 1e8;
        creator.setRewardTokenMinAmounts(tokens, amounts);
        vm.stopPrank();

        angle.mint(address(alice), 1e22);
        vm.prank(alice);
        angle.approve(address(creator), type(uint256).max);

        agEUR.mint(address(alice), 1e22);
        vm.prank(alice);
        agEUR.approve(address(creator), type(uint256).max);

        vm.stopPrank();
    }

    function testUnit_ReallocationCampaignRewards_revertWhen_TooSoon() public {
        IERC20 rewardToken = IERC20(address(agEUR));
        uint256 amount = 100 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 48,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        {
            address[] memory users = new address[](1);
            users[0] = bob;

            vm.prank(alice);
            vm.expectRevert(Errors.InvalidReallocation.selector);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(0));
            address[] memory listReallocation = creator.getCampaignListReallocation(campaignId);
            assertEq(listReallocation.length, 0);
        }
    }

    function testUnit_ReallocationCampaignRewards_Success() public {
        IERC20 rewardToken = IERC20(address(angle));
        uint256 amount = 100 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.prank(governor);
        // Create false tree
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        agEUR.mint(address(distributor), 5e17);

        vm.warp(distributor.endOfDisputePeriod() + 1);
        {
            bytes32[][] memory proofs = new bytes32[][](1);
            address[] memory users = new address[](1);
            address[] memory tokens = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            // proofs[0] = new bytes32[](1);
            // proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
            // users[0] = alice;
            // tokens[0] = address(angle);
            // amounts[0] = 1e18;
            proofs[0] = new bytes32[](1);
            proofs[0][0] = bytes32(0x3a64e591d79db8530701e6f3dbdd95dc74681291b327d0ce4acc97024a61430c);
            users[0] = bob;
            tokens[0] = address(agEUR);
            amounts[0] = 5e17;

            uint256 aliceBalance = angle.balanceOf(address(alice));
            uint256 bobBalance = agEUR.balanceOf(address(bob));

            vm.prank(bob);
            distributor.claim(users, tokens, amounts, proofs);
        }

        {
            address[] memory users = new address[](1);
            users[0] = alice;

            vm.prank(bob);
            vm.expectRevert(Errors.OperatorNotAllowed.selector);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(0));
        }

        {
            address[] memory users = new address[](1);
            users[0] = alice;

            vm.prank(alice);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(governor));

            address[] memory listReallocation = creator.getCampaignListReallocation(campaignId);
            assertEq(listReallocation.length, 1);
            assertEq(listReallocation[0], alice);
        }

        {
            address[] memory users = new address[](3);
            users[0] = alice;
            users[1] = bob;
            users[2] = dylan;

            vm.prank(alice);
            creator.reallocateCampaignRewards(campaignId, users, address(guardian));

            assertEq(creator.campaignReallocation(campaignId, alice), address(guardian));
            assertEq(creator.campaignReallocation(campaignId, bob), address(guardian));
            assertEq(creator.campaignReallocation(campaignId, dylan), address(guardian));

            address[] memory listReallocation = creator.getCampaignListReallocation(campaignId);
            assertEq(listReallocation.length, 4);
            assertEq(listReallocation[0], alice);
            assertEq(listReallocation[1], alice);
            assertEq(listReallocation[2], bob);
            assertEq(listReallocation[3], dylan);
        }
    }

    function testUnit_ReallocationCampaignRewards_SuccessWhenOperator() public {
        IERC20 rewardToken = IERC20(address(angle));
        uint256 amount = 100 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.prank(governor);
        // Create false tree
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        agEUR.mint(address(distributor), 5e17);

        vm.warp(distributor.endOfDisputePeriod() + 1);
        {
            bytes32[][] memory proofs = new bytes32[][](1);
            address[] memory users = new address[](1);
            address[] memory tokens = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            // proofs[0] = new bytes32[](1);
            // proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
            // users[0] = alice;
            // tokens[0] = address(angle);
            // amounts[0] = 1e18;
            proofs[0] = new bytes32[](1);
            proofs[0][0] = bytes32(0x3a64e591d79db8530701e6f3dbdd95dc74681291b327d0ce4acc97024a61430c);
            users[0] = bob;
            tokens[0] = address(agEUR);
            amounts[0] = 5e17;

            uint256 aliceBalance = angle.balanceOf(address(alice));
            uint256 bobBalance = agEUR.balanceOf(address(bob));

            vm.prank(bob);
            distributor.claim(users, tokens, amounts, proofs);
        }

        {
            address[] memory users = new address[](1);
            users[0] = alice;

            vm.prank(bob);
            vm.expectRevert(Errors.OperatorNotAllowed.selector);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(0));
        }

        {
            address[] memory users = new address[](1);
            users[0] = alice;

            vm.prank(alice);
            creator.toggleCampaignOperator(alice, bob);
            vm.prank(dylan);
            vm.expectRevert();
            creator.reallocateCampaignRewards(campaignId, users, address(governor));
            vm.prank(bob);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(governor));

            address[] memory listReallocation = creator.getCampaignListReallocation(campaignId);
            assertEq(listReallocation.length, 1);
            assertEq(listReallocation[0], alice);
        }
    }

    function testUnit_ReallocationCampaignRewards_SuccessWhenGovernor() public {
        IERC20 rewardToken = IERC20(address(angle));
        uint256 amount = 100 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.prank(governor);
        creator.toggleCampaignOperator(alice, governor);
        // Create false tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        agEUR.mint(address(distributor), 5e17);

        vm.warp(distributor.endOfDisputePeriod() + 1);
        {
            bytes32[][] memory proofs = new bytes32[][](1);
            address[] memory users = new address[](1);
            address[] memory tokens = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            // proofs[0] = new bytes32[](1);
            // proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
            // users[0] = alice;
            // tokens[0] = address(angle);
            // amounts[0] = 1e18;
            proofs[0] = new bytes32[](1);
            proofs[0][0] = bytes32(0x3a64e591d79db8530701e6f3dbdd95dc74681291b327d0ce4acc97024a61430c);
            users[0] = bob;
            tokens[0] = address(agEUR);
            amounts[0] = 5e17;

            vm.prank(bob);
            distributor.claim(users, tokens, amounts, proofs);
        }

        {
            address[] memory users = new address[](1);
            users[0] = alice;

            vm.prank(bob);
            vm.expectRevert(Errors.OperatorNotAllowed.selector);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(0));
        }

        {
            address[] memory users = new address[](1);
            users[0] = alice;

            vm.prank(governor);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(governor));

            address[] memory listReallocation = creator.getCampaignListReallocation(campaignId);
            assertEq(listReallocation.length, 1);
            assertEq(listReallocation[0], alice);
        }
    }
}

contract DistributionCreatorOverrideTest is Fixture {
    using SafeERC20 for IERC20;

    uint256 constant maxDistribForOOG = 1e4;
    uint256 constant nbrDistrib = 10;
    uint32 initStartTime;
    uint32 initEndTime;
    uint32 startTime;
    uint32 endTime;
    uint32 numEpoch;

    bytes32 campaignId;
    address campaignCreator;
    address campaignRewardToken;
    uint256 campaignAmount;
    uint256 campaignType;
    uint32 campaignStartTimestamp;
    uint32 campaignDuration;
    bytes campaignCampaignData;
    uint256[] timestamps;

    uint256 amount;
    uint256 amountAfterFees;
    uint32 startTimestamp;
    bytes campaignData;

    function setUp() public override {
        super.setUp();

        initStartTime = uint32(block.timestamp);
        numEpoch = 25;
        initEndTime = startTime + numEpoch * EPOCH_DURATION;

        vm.startPrank(guardian);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(angle);
        amounts[0] = 1e8;
        creator.setRewardTokenMinAmounts(tokens, amounts);
        vm.stopPrank();

        angle.mint(address(alice), 1e22);
        vm.prank(alice);
        angle.approve(address(creator), type(uint256).max);

        vm.stopPrank();
    }

    function testUnit_OverrideCampaignData_RevertWhen_IncorrectCampaignId() public {
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);

        // Silo distrib data
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory overrideCampaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.expectRevert(Errors.CampaignDoesNotExist.selector);
        vm.prank(alice);
        creator.overrideCampaign(
            keccak256("test"),
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: overrideCampaignData
            })
        );
    }

    function testUnit_OverrideCampaignDataFromOperator() public {
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory overrideCampaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.prank(alice);
        creator.toggleCampaignOperator(alice, bob);

        vm.prank(dylan);
        vm.expectRevert(Errors.OperatorNotAllowed.selector);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: overrideCampaignData
            })
        );

        vm.prank(bob);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: overrideCampaignData
            })
        );

        (
            ,
            campaignCreator,
            campaignRewardToken,
            campaignAmount,
            campaignType,
            campaignStartTimestamp,
            campaignDuration,
            campaignCampaignData
        ) = creator.campaignOverrides(campaignId);

        assertEq(campaignCreator, alice);
        assertEq(campaignRewardToken, address(angle));
        assertEq(campaignAmount, amountAfterFees);
        assertEq(campaignType, 5);
        assertEq(campaignStartTimestamp, startTimestamp);
        assertEq(campaignDuration, 3600 * 24);
        assertEq(campaignCampaignData, overrideCampaignData);
        assertGe(creator.campaignOverridesTimestamp(campaignId, 0), startTimestamp);
        vm.expectRevert();
        creator.campaignOverridesTimestamp(campaignId, 1);
    }

    function testUnit_OverrideCampaignDataFromGovernor() public {
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );

        vm.prank(governor);
        creator.toggleCampaignOperator(alice, governor);

        vm.warp(block.timestamp + 1000);
        vm.roll(4);

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory overrideCampaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.prank(governor);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: overrideCampaignData
            })
        );

        (
            ,
            campaignCreator,
            campaignRewardToken,
            campaignAmount,
            campaignType,
            campaignStartTimestamp,
            campaignDuration,
            campaignCampaignData
        ) = creator.campaignOverrides(campaignId);

        assertEq(campaignCreator, alice);
        assertEq(campaignRewardToken, address(angle));
        assertEq(campaignAmount, amountAfterFees);
        assertEq(campaignType, 5);
        assertEq(campaignStartTimestamp, startTimestamp);
        assertEq(campaignDuration, 3600 * 24);
        assertEq(campaignCampaignData, overrideCampaignData);
        assertGe(creator.campaignOverridesTimestamp(campaignId, 0), startTimestamp);
        vm.expectRevert();
        creator.campaignOverridesTimestamp(campaignId, 1);
    }

    function testUnit_OverrideCampaignData() public {
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(angle),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory overrideCampaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(angle),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: overrideCampaignData
            })
        );

        (
            ,
            campaignCreator,
            campaignRewardToken,
            campaignAmount,
            campaignType,
            campaignStartTimestamp,
            campaignDuration,
            campaignCampaignData
        ) = creator.campaignOverrides(campaignId);

        assertEq(campaignCreator, alice);
        assertEq(campaignRewardToken, address(angle));
        assertEq(campaignAmount, amountAfterFees);
        assertEq(campaignType, 5);
        assertEq(campaignStartTimestamp, startTimestamp);
        assertEq(campaignDuration, 3600 * 24);
        assertEq(campaignCampaignData, overrideCampaignData);
        assertGe(creator.campaignOverridesTimestamp(campaignId, 0), startTimestamp);
        vm.expectRevert();
        creator.campaignOverridesTimestamp(campaignId, 1);
    }

    function testUnit_OverrideCampaignData_RevertWhen_IncorrectCreator() public {
        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        campaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.expectRevert(Errors.OperatorNotAllowed.selector);
        vm.prank(bob);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: bob,
                rewardToken: address(rewardToken),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );

        vm.expectRevert(Errors.OperatorNotAllowed.selector);
        vm.prank(bob);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );
    }

    function testUnit_OverrideCampaignData_RevertWhen_IncorrectRewardToken() public {
        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        campaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.expectRevert(Errors.InvalidOverride.selector);
        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(alice),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );
    }

    function testUnit_OverrideCampaignData_RevertWhen_IncorrectRewardAmount() public {
        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        campaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.expectRevert(Errors.InvalidOverride.selector);
        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(alice),
                amount: amount,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );
    }

    function testUnit_OverrideCampaignData_RevertWhen_IncorrectStartTimestamp() public {
        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        campaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.expectRevert(Errors.InvalidOverride.selector);
        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 5,
                startTimestamp: startTimestamp + 1,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );
    }

    function testUnit_OverrideCampaignData_RevertWhen_IncorrectDuration() public {
        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);

        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: abi.encode(
                    0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
                    new address[](0),
                    new address[](0),
                    "",
                    new bytes[](0),
                    new bytes[](0),
                    hex""
                )
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        campaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.expectRevert(Errors.InvalidOverride.selector);
        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 399,
                campaignData: campaignData
            })
        );
    }

    function testUnit_OverrideCampaignDuration() public {
        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);
        uint32 duration = 3600 * 24;
        uint32 durationAfterOverride = 3600 * 12;

        campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );
        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: duration,
                campaignData: campaignData
            })
        );

        CampaignParameters memory campaign = creator.campaign(campaignId);
        assertEq(campaign.creator, alice);
        assertEq(campaign.rewardToken, address(rewardToken));
        assertEq(campaign.amount, (amount * (1e9 - creator.defaultFees())) / 1e9);
        assertEq(campaign.campaignType, 1);
        assertEq(campaign.startTimestamp, startTimestamp);
        assertEq(campaign.duration, duration);

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amountAfterFees,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: durationAfterOverride,
                campaignData: campaignData
            })
        );

        (
            ,
            campaignCreator,
            campaignRewardToken,
            campaignAmount,
            campaignType,
            campaignStartTimestamp,
            campaignDuration,
            campaignCampaignData
        ) = creator.campaignOverrides(campaignId);
        assertEq(campaignCreator, alice);
        assertEq(campaignRewardToken, address(rewardToken));
        assertEq(campaignAmount, amountAfterFees);
        assertEq(campaignType, 1);
        assertEq(campaignStartTimestamp, startTimestamp);
        assertEq(campaignDuration, durationAfterOverride);
        assertEq(campaignCampaignData, campaignData);
        assertGe(creator.campaignOverridesTimestamp(campaignId, 0), startTimestamp);
        vm.expectRevert();
        creator.campaignOverridesTimestamp(campaignId, 1);
    }

    function testUnit_GetCampaignOverridesTimestamp() public {
        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);
        uint32 duration = 3600 * 24;
        uint32 durationAfterOverride = 3600 * 12;

        campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );
        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: duration,
                campaignData: campaignData
            })
        );

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amountAfterFees,
                campaignType: 10,
                startTimestamp: startTimestamp,
                duration: durationAfterOverride * 10,
                campaignData: campaignData
            })
        );

        timestamps = creator.getCampaignOverridesTimestamp(campaignId);
        assertEq(timestamps.length, 1);
        assertEq(timestamps[0], 1001);
    }

    function testUnit_OverrideCampaignAdditionalFee() public {
        vm.prank(governor);
        creator.setCampaignFees(3, 1e7);

        IERC20 rewardToken = IERC20(address(angle));
        amount = 100 ether;
        amountAfterFees = 90 ether;
        startTimestamp = uint32(block.timestamp + 600);
        uint32 duration = 3600 * 24;
        uint32 durationAfterOverride = 3600 * 12;

        uint256 prevBalance = rewardToken.balanceOf(alice);

        campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );
        vm.prank(alice);
        campaignId = creator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: duration,
                campaignData: campaignData
            })
        );

        assertEq(rewardToken.balanceOf(alice), prevBalance - amount);

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override
        vm.prank(alice);
        creator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: alice,
                rewardToken: address(rewardToken),
                amount: amountAfterFees,
                campaignType: 3,
                startTimestamp: startTimestamp,
                duration: durationAfterOverride,
                campaignData: campaignData
            })
        );

        assertEq(rewardToken.balanceOf(alice), prevBalance - amount);
    }
}

contract UpgradeDistributionCreatorTest is Test {
    DistributionCreator public distributionCreator;
    Distributor public distributor;
    IAccessControlManager public accessControlManager;
    address public deployer;
    address public governor;
    IERC20 public rewardToken;
    uint256 public chainId;
    bytes32 public campaignId0;
    bytes32 public campaignId73;
    bytes32 public testCampaignId;

    function setUp() public {
        // Setup environment variables
        deployer = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701; // deploy
        vm.createSelectFork(vm.envString("BASE_NODE_URI"));
        chainId = block.chainid;
        // Load existing contracts
        distributor = Distributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);
        distributionCreator = DistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
        governor = 0x19c41F6607b2C0e80E84BaadaF886b17565F278e;
        accessControlManager = IAccessControlManager(0xC16B81Af351BA9e64C1a069E3Ab18c244A1E3049);
        rewardToken = IERC20(0xC011882d0f7672D8942e7fE2248C174eeD640c8f); // aglaMerkl

        // Setup test campaign parameters
        uint256 amount = 10 ether;
        uint32 startTimestamp = uint32(block.timestamp + 3600); // 1 hour from now
        uint32 duration = 3600 * 6;
        uint32 campaignType = 1;
        bytes memory campaignData = abi.encode(
            0x70F796946eD919E4Bc6cD506F8dACC45E4539771,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        // Mint tokens and approve for test campaign
        vm.startPrank(deployer);
        MockToken(address(rewardToken)).mint(deployer, amount);
        rewardToken.approve(address(distributionCreator), amount);
        distributionCreator.acceptConditions();

        // Create test campaign
        testCampaignId = distributionCreator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: deployer,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: campaignType,
                startTimestamp: startTimestamp,
                duration: duration,
                campaignData: campaignData
            })
        );
        vm.stopPrank();

        // Deploy new implementation
        vm.startPrank(deployer);
        address creatorImpl = address(new DistributionCreator());
        vm.stopPrank();

        // Upgrade
        vm.startPrank(governor);
        distributionCreator.upgradeTo(address(creatorImpl));
        vm.stopPrank();
    }

    function test_VerifyStorageSlots_Success() public {
        // Verify storage slots remain unchanged
        assertEq(address(distributionCreator.accessControlManager()), 0xC16B81Af351BA9e64C1a069E3Ab18c244A1E3049);
        assertEq(address(distributionCreator.distributor()), 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);
        assertEq(distributionCreator.defaultFees(), 0.03e9);

        // Verify message and hash
        assertEq(distributionCreator.messageHash(), 0x08dabc24dcfcb230453d08bce47c730ed6f1cce205bc153680488959b503644e);

        // Verify distribution list entries

        // Verify fee and whitelist settings
        address testAddr = 0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185;
        assertEq(distributionCreator.feeRebate(testAddr), 0);
        assertEq(distributionCreator.isWhitelistedToken(0xA61BeB4A3d02decb01039e378237032B351125B4), 1);
        assertEq(distributionCreator._nonces(testAddr), 4);
        assertEq(distributionCreator.userSignatures(testAddr), 0x08dabc24dcfcb230453d08bce47c730ed6f1cce205bc153680488959b503644e);
        assertEq(distributionCreator.userSignatureWhitelist(testAddr), 0);

        // Verify reward tokens
        assertEq(distributionCreator.rewardTokens(0), 0x7D49a065D17d6d4a55dc13649901fdBB98B2AFBA);
        assertEq(distributionCreator.rewardTokens(21), 0xF734eFdE0C424BA2B547b186586dE417b0954802);
        assertEq(distributionCreator.rewardTokenMinAmounts(0x7D49a065D17d6d4a55dc13649901fdBB98B2AFBA), 1 ether);

        // Verify campaign list
        {
            (bytes32 campaignId, , , , , , , ) = distributionCreator.campaignList(0);
            assertEq(campaignId, 0x4e2bf13f682a244a80e0f25e1545fc8ad3a181d60658d22a3d347ee493e2a740);
        }
        {
            (bytes32 campaignId, , , , , , , ) = distributionCreator.campaignList(67);
            assertEq(campaignId, 0xf7d416acc480a41cd4cbb1bd68941f2f585adb659bd95d45e193589175356972);
        }

        // Verify campaign fees
        assertEq(distributionCreator.campaignSpecificFees(4), 0.005e9);

        // Verify campaign overrides
        {
            (bytes32 campaignId, , , , , , , ) = distributionCreator.campaignOverrides(
                0xf7d416acc480a41cd4cbb1bd68941f2f585adb659bd95d45e193589175356972
            );
            assertEq(campaignId, bytes32(0));
        }

        // Verify revert on invalid campaign override timestamp
        vm.expectRevert();
        distributionCreator.campaignOverridesTimestamp(0x4e2bf13f682a244a80e0f25e1545fc8ad3a181d60658d22a3d347ee493e2a740, 0);
    }

    function test_UpgradeTo_Revert_WhenNonGovernor() public {
        vm.startPrank(deployer);
        address creatorImpl = address(new DistributionCreator());
        vm.stopPrank();

        // Should revert when non-governor tries to upgrade
        address nonGovernor = makeAddr("nonGovernor");
        vm.startPrank(nonGovernor);
        vm.expectRevert();
        distributionCreator.upgradeTo(address(creatorImpl));
        vm.stopPrank();
    }

    function test_Claim_Success() public {
        address updater = 0x435046800Fb9149eE65159721A92cB7d50a7534b;

        MerkleTree memory newTree = MerkleTree({
            merkleRoot: 0xb402de8ed2f573c780a39e6d41aa5276706c439849d1e4925d379f2aa8913577,
            ipfsHash: bytes32(0)
        });

        // Perform tree update
        vm.startPrank(updater);
        vm.warp(distributor.endOfDisputePeriod() + 1); // can't update tree before dispute period is over
        assertEq(distributor.canUpdateMerkleRoot(updater), 1);
        distributor.updateTree(newTree);
        vm.stopPrank();

        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Verify tree update
        (bytes32 currentRoot, bytes32 currentHash) = distributor.tree();
        assertEq(currentRoot, newTree.merkleRoot);
        assertEq(currentHash, newTree.ipfsHash);

        address claimer = 0x15775b23340C0f50E0428D674478B0e9D3D0a759;
        uint256 balanceToClaim = 1918683165360;

        // Setup claim parameters
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        proofs[0] = new bytes32[](17);
        proofs[0][0] = 0xb4273243bd0ec5add5e6d803f13bf6866ed1904d24626766ab2836454ba1ec0a;
        proofs[0][1] = 0x3ee0ead23e2fe3f664ccb5e13683f27e27a4d7fefa8405545fb6421244630375;
        proofs[0][2] = 0x69f54e33351af15236b33bb4695470f1af96cd1a9f154aa511ff16faa6886791;
        proofs[0][3] = 0xa9d77ad46850fbfb8c196c693acdbb0c6241a2e561a8b0073ec71297a565673d;
        proofs[0][4] = 0xe1b57f280e556c7f217e8d375f0cef7977a9467d5496d32bb8ec461f0d4c4f19;
        proofs[0][5] = 0x0fc7ddc7cc9ecc7f7b0be5692f671394f6245ffdabe5c0fd2062eb71b7c11826;
        proofs[0][6] = 0x94445a98fe6679760e5ac2edeacfe0bfa397f805c7adeaf3558a82accb78f201;
        proofs[0][7] = 0x14a6fec66cdfece5c73ec44196f1414326236131ff9a60350cca603e54985c4e;
        proofs[0][8] = 0x84679751230af3e3242ea1cecfc8daee3d2187ab647281cbf8c52e649a43e84c;
        proofs[0][9] = 0xc0fc15960178fe4d542c93e64ec58648e5ff17bd02b27f841bd6ab838fc5ee67;
        proofs[0][10] = 0x9b84efe5d11bc4de32ecd204c3962dd9270694d93a50e2840d763eaeac6c194b;
        proofs[0][11] = 0x5c8025dbe663cf4b4e19fbc7b1e54259af5822fd774fd60a98e7c7a60112efe0;
        proofs[0][12] = 0x301b573f9a6503ebe00ff7031a33cd41170d8b4c09a31fcafb9feb7529400a79;
        proofs[0][13] = 0xc89942ad2dcb0ac96d2620ef9475945bdbe6d40a9f6c4e9f6d9437a953bf881c;
        proofs[0][14] = 0xce6ca90077dc547f9a52a24d2636d659642fbae1d16c81c9e47c5747a472c63f;
        proofs[0][15] = 0xe34667d2e10b515dd1f7b29dcd7990d25ea9caa7a7de571c4fb221c0a8fc82a1;
        proofs[0][16] = 0x8316d6488fd22b823cc35ee673297ea2a753f0a89e5384ef20b38d053c881628;

        users[0] = claimer;
        tokens[0] = address(rewardToken);
        amounts[0] = balanceToClaim;

        // Record initial balance
        uint256 initialBalance = rewardToken.balanceOf(claimer);

        // Perform claim
        vm.prank(claimer);
        distributor.claim(users, tokens, amounts, proofs);

        // Verify claim result
        assertEq(rewardToken.balanceOf(claimer), initialBalance + balanceToClaim);
    }

    function test_ReallocateCampaignRewards_Success_ReallocateCampaignRewards() public {
        address to = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;

        address[] memory froms = new address[](2);
        froms[0] = 0x15775b23340C0f50E0428D674478B0e9D3D0a759;
        froms[1] = 0xe4BB74804edf5280c9203f034036f7CB15196078;

        vm.warp(distributionCreator.campaign(testCampaignId).startTimestamp + distributionCreator.campaign(testCampaignId).duration + 1);

        // Perform reallocation
        vm.prank(deployer);
        distributionCreator.reallocateCampaignRewards(testCampaignId, froms, to);

        // Verify reallocation results
        assertEq(distributionCreator.campaignReallocation(testCampaignId, froms[0]), to);
        assertEq(distributionCreator.campaignListReallocation(testCampaignId, 0), froms[0]);
        assertEq(distributionCreator.campaignListReallocation(testCampaignId, 1), froms[1]);
    }

    function test_OverrideCampaign_Success_UpdateCampaign() public {
        uint256 amount = distributionCreator.campaign(testCampaignId).amount;
        uint32 startTimestamp = distributionCreator.campaign(testCampaignId).startTimestamp;
        uint32 duration = distributionCreator.campaign(testCampaignId).duration + 3600;

        // Setup campaign data
        uint32 campaignType = 1;
        bytes memory campaignData = abi.encode(
            0x70F796946eD919E4Bc6cD506F8dACC45E4539771,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );

        // Mint tokens for test
        vm.startPrank(deployer);
        MockToken(address(rewardToken)).mint(deployer, amount);
        rewardToken.approve(address(distributionCreator), amount);

        // Perform campaign update
        distributionCreator.overrideCampaign(
            testCampaignId,
            CampaignParameters({
                campaignId: testCampaignId,
                creator: deployer,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: campaignType,
                startTimestamp: startTimestamp,
                duration: duration,
                campaignData: campaignData
            })
        );

        // Verify campaign update
        (
            ,
            address campaignCreator,
            address campaignRewardToken,
            uint256 campaignAmount,
            uint256 campaignType_,
            uint32 campaignStartTimestamp,
            uint32 campaignDuration,
            bytes memory campaignData_
        ) = distributionCreator.campaignOverrides(testCampaignId);

        assertEq(campaignCreator, deployer);
        assertEq(campaignRewardToken, address(rewardToken));
        assertEq(campaignAmount, amount);
        assertEq(campaignType_, campaignType);
        assertEq(campaignStartTimestamp, startTimestamp);
        assertEq(campaignDuration, duration);
        assertEq(campaignData_, campaignData);

        vm.stopPrank();
    }

    function test_OverrideCampaign_Success_WhenCreator() public {
        vm.startPrank(distributionCreator.campaign(testCampaignId).creator);

        IERC20(address(rewardToken)).approve(address(distributionCreator), distributionCreator.campaign(testCampaignId).amount);
        CampaignParameters memory newCampaign = CampaignParameters({
            campaignId: testCampaignId,
            creator: distributionCreator.campaign(testCampaignId).creator,
            rewardToken: distributionCreator.campaign(testCampaignId).rewardToken,
            amount: distributionCreator.campaign(testCampaignId).amount,
            campaignType: distributionCreator.campaign(testCampaignId).campaignType,
            startTimestamp: distributionCreator.campaign(testCampaignId).startTimestamp,
            duration: distributionCreator.campaign(testCampaignId).duration,
            campaignData: distributionCreator.campaign(testCampaignId).campaignData
        });

        distributionCreator.overrideCampaign(testCampaignId, newCampaign);
        vm.stopPrank();
    }

    function test_OverrideCampaign_Success_WhenCreator_UpdateStartTimestampBeforeCampaignStart() public {
        vm.startPrank(distributionCreator.campaign(testCampaignId).creator);

        vm.warp(distributionCreator.campaign(testCampaignId).startTimestamp - 2);
        IERC20(address(rewardToken)).approve(address(distributionCreator), distributionCreator.campaign(testCampaignId).amount);
        CampaignParameters memory newCampaign = CampaignParameters({
            campaignId: testCampaignId,
            creator: distributionCreator.campaign(testCampaignId).creator,
            rewardToken: distributionCreator.campaign(testCampaignId).rewardToken,
            amount: distributionCreator.campaign(testCampaignId).amount,
            campaignType: distributionCreator.campaign(testCampaignId).campaignType,
            startTimestamp: distributionCreator.campaign(testCampaignId).startTimestamp + 3600,
            duration: distributionCreator.campaign(testCampaignId).duration,
            campaignData: distributionCreator.campaign(testCampaignId).campaignData
        });

        distributionCreator.overrideCampaign(testCampaignId, newCampaign);
        vm.stopPrank();
    }

    function test_OverrideCampaign_Revert_WhenCreator_UpdateStartTimestampAfterCampaignStart() public {
        vm.startPrank(distributionCreator.campaign(testCampaignId).creator);

        vm.warp(distributionCreator.campaign(testCampaignId).startTimestamp + 1);
        IERC20(address(rewardToken)).approve(address(distributionCreator), distributionCreator.campaign(testCampaignId).amount);
        CampaignParameters memory newCampaign = CampaignParameters({
            campaignId: testCampaignId,
            creator: distributionCreator.campaign(testCampaignId).creator,
            rewardToken: distributionCreator.campaign(testCampaignId).rewardToken,
            amount: distributionCreator.campaign(testCampaignId).amount,
            campaignType: distributionCreator.campaign(testCampaignId).campaignType,
            startTimestamp: distributionCreator.campaign(testCampaignId).startTimestamp + 3600,
            duration: distributionCreator.campaign(testCampaignId).duration + 3600,
            campaignData: distributionCreator.campaign(testCampaignId).campaignData
        });

        vm.expectRevert(Errors.InvalidOverride.selector);
        distributionCreator.overrideCampaign(testCampaignId, newCampaign);
        vm.stopPrank();
    }

    function test_OverrideCampaign_Revert_WhenNonCreator() public {
        address bob = makeAddr("bob");
        vm.startPrank(bob);

        CampaignParameters memory newCampaign = CampaignParameters({
            campaignId: testCampaignId,
            creator: distributionCreator.campaign(testCampaignId).creator,
            rewardToken: distributionCreator.campaign(testCampaignId).rewardToken,
            amount: distributionCreator.campaign(testCampaignId).amount,
            campaignType: distributionCreator.campaign(testCampaignId).campaignType,
            startTimestamp: distributionCreator.campaign(testCampaignId).startTimestamp,
            duration: distributionCreator.campaign(testCampaignId).duration,
            campaignData: distributionCreator.campaign(testCampaignId).campaignData
        });
        vm.expectRevert(Errors.OperatorNotAllowed.selector);
        distributionCreator.overrideCampaign(testCampaignId, newCampaign);
        vm.stopPrank();
    }
}
