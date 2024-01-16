// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DistributionParameters } from "../../contracts/DistributionCreator.sol";
import "./Fixture.t.sol";

contract DistributionCreatorTest is Fixture {
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

        address[] memory positionWrappers = new address[](3);
        uint32[] memory wrapperTypes = new uint32[](3);
        positionWrappers[0] = alice;
        positionWrappers[1] = bob;
        positionWrappers[2] = charlie;
        wrapperTypes[0] = 0;
        wrapperTypes[1] = 1;
        wrapperTypes[2] = 2;

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

        vm.warp(startTime + 3600 * 24 * 1000);
        startTime = uint32(block.timestamp);
        endTime = startTime + numEpoch * EPOCH_DURATION;
        params.epochStart = startTime;
        for (uint256 i; i < nbrDistrib; i++) creator.createDistribution(params);

        vm.stopPrank();
    }

    /*
    // Commented because of an update in Foundry which does not handle well out of gas issues
    function testFuzz_GetDistributionsOutOfGas() public {
        address[] memory positionWrappers = new address[](3);
        uint32[] memory wrapperTypes = new uint32[](3);
        positionWrappers[0] = alice;
        positionWrappers[1] = bob;
        positionWrappers[2] = charlie;
        wrapperTypes[0] = 0;
        wrapperTypes[1] = 1;
        wrapperTypes[2] = 2;

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
            epochStart: startTime,
            numEpoch: 25,
            boostedReward: 0,
            boostingAddress: address(0),
            rewardId: keccak256("TEST"),
            additionalData: hex""
        });

        vm.warp(startTime + 3600 * 24 * 10);
        startTime = uint32(block.timestamp);
        endTime = startTime + numEpoch * EPOCH_DURATION;
        params.epochStart = startTime;
        for (uint256 i; i < maxDistribForOOG; i++) creator.createDistribution(params);

        vm.stopPrank();
        // All calls will revert because it is oog
        vm.expectRevert();
        creator.getActiveDistributions();

        vm.expectRevert();
        creator.getDistributionsForEpoch(startTime);

        vm.expectRevert();
        creator.getDistributionsBetweenEpochs(startTime, endTime);

        vm.expectRevert();
        creator.getDistributionsAfterEpoch(startTime);

        vm.expectRevert();
        creator.getActivePoolDistributions(address(pool));

        vm.expectRevert();
        creator.getPoolDistributionsForEpoch(address(pool), startTime);

        vm.expectRevert();
        creator.getPoolDistributionsBetweenEpochs(address(pool), startTime, endTime);

        vm.expectRevert();
        creator.getPoolDistributionsAfterEpoch(address(pool), startTime);
    }
    */

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 WITH DIFFERENT POOLS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
}
