// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DistributionParameters } from "../../contracts/DistributionCreator.sol";
import "./Fixture.t.sol";
import { CampaignParameters } from "contracts/DistributionCreator.sol";
import { Distributor, MerkleTree } from "contracts/Distributor.sol";
import "contracts/utils/Errors.sol" as Errors;

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
        creator.toggleSigningWhitelist(alice);
        creator.toggleTokenWhitelist(address(agEUR));
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
        distributor.initialize(IAccessControlManager(address(coreBorrow)));

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
        creator.toggleSigningWhitelist(alice);
        creator.toggleTokenWhitelist(address(agEUR));
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
            vm.prank(bob);
            distributor.claim(users, tokens, amounts, proofs);
        }

        {
            address[] memory users = new address[](1);
            users[0] = bob;

            vm.prank(alice);
            vm.expectRevert(Errors.InvalidOverride.selector);
            creator.reallocateCampaignRewards(campaignId, users, address(governor));

            assertEq(creator.campaignReallocation(campaignId, alice), address(0));
            address[] memory listReallocation = creator.getCampaignListReallocation(campaignId);
            assertEq(listReallocation.length, 0);
        }
    }

    function testUnit_ReallocationCampaignRewards_revertWhen_AlreadyClaimed() public {
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
            vm.prank(bob);
            distributor.claim(users, tokens, amounts, proofs);
        }

        {
            address[] memory users = new address[](1);
            users[0] = bob;

            vm.prank(alice);
            vm.expectRevert(Errors.InvalidOverride.selector);
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
            vm.expectRevert(Errors.InvalidOverride.selector);
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

    function setUp() public override {
        super.setUp();

        initStartTime = uint32(block.timestamp);
        numEpoch = 25;
        initEndTime = startTime + numEpoch * EPOCH_DURATION;

        vm.startPrank(guardian);
        creator.toggleSigningWhitelist(alice);
        creator.toggleTokenWhitelist(address(agEUR));
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

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory campaignData = abi.encode(
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
                rewardToken: address(rewardToken),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );
    }

    function testUnit_OverrideCampaignData_RevertWhen_IncorrectCreator() public {
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

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory campaignData = abi.encode(
            0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
            2,
            0xa42001D6d2237d2c74108FE360403C4b796B7170,
            whitelist,
            new address[](0),
            hex""
        );

        vm.expectRevert(Errors.InvalidOverride.selector);
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

        vm.expectRevert(Errors.InvalidOverride.selector);
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

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory campaignData = abi.encode(
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

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory campaignData = abi.encode(
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

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory campaignData = abi.encode(
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

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory campaignData = abi.encode(
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

    function testUnit_OverrideCampaignData() public {
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

        vm.warp(block.timestamp + 1000);
        vm.roll(4);
        // override

        // Silo distrib
        address[] memory whitelist = new address[](1);
        whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        bytes memory campaignData = abi.encode(
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
                rewardToken: address(rewardToken),
                amount: amountAfterFees,
                campaignType: 5,
                startTimestamp: startTimestamp,
                duration: 3600 * 24,
                campaignData: campaignData
            })
        );

        (
            ,
            address campaignCreator,
            address campaignRewardToken,
            uint256 campaignAmount,
            uint256 campaignType,
            uint32 campaignStartTimestamp,
            uint32 campaignDuration,
            bytes memory campaignCampaignData
        ) = creator.campaignOverrides(campaignId);
        assertEq(campaignCreator, alice);
        assertEq(campaignRewardToken, address(rewardToken));
        assertEq(campaignAmount, amountAfterFees);
        assertEq(campaignType, 5);
        assertEq(campaignStartTimestamp, startTimestamp);
        assertEq(campaignDuration, 3600 * 24);
        assertEq(campaignCampaignData, campaignData);
        assertGe(creator.campaignOverridesTimestamp(campaignId, 0), startTimestamp);
        vm.expectRevert();
        creator.campaignOverridesTimestamp(campaignId, 1);
    }

    function testUnit_OverrideCampaignDuration() public {
        IERC20 rewardToken = IERC20(address(angle));
        uint256 amount = 100 ether;
        uint256 amountAfterFees = 90 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);
        uint32 duration = 3600 * 24;
        uint32 durationAfterOverride = 3600 * 12;

        bytes memory campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );
        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
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
            address campaignCreator,
            address campaignRewardToken,
            uint256 campaignAmount,
            uint256 campaignType,
            uint32 campaignStartTimestamp,
            uint32 campaignDuration,
            bytes memory campaignCampaignData
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
        uint256 amount = 100 ether;
        uint256 amountAfterFees = 90 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);
        uint32 duration = 3600 * 24;
        uint32 durationAfterOverride = 3600 * 12;

        bytes memory campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );
        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
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
                campaignType: 1,
                startTimestamp: startTimestamp,
                duration: durationAfterOverride,
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

        uint256[] memory timestamps = creator.getCampaignOverridesTimestamp(campaignId);
        assertEq(timestamps.length, 2);
        assertEq(timestamps[0], 1001);
        assertEq(timestamps[1], 2001);
    }

    function testUnit_OverrideCampaignAdditionalFee() public {
        vm.prank(governor);
        creator.setCampaignFees(3, 1e7);

        IERC20 rewardToken = IERC20(address(angle));
        uint256 amount = 100 ether;
        uint256 amountAfterFees = 90 ether;
        uint32 startTimestamp = uint32(block.timestamp + 600);
        uint32 duration = 3600 * 24;
        uint32 durationAfterOverride = 3600 * 12;

        uint256 prevBalance = rewardToken.balanceOf(alice);

        bytes memory campaignData = abi.encode(
            0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            new bytes[](0),
            hex""
        );
        vm.prank(alice);
        bytes32 campaignId = creator.createCampaign(
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

        assertEq(rewardToken.balanceOf(alice), prevBalance - amount - (amountAfterFees * 1e7) / 1e9);
    }
}
