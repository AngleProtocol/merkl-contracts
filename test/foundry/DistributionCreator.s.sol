// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DistributionParameters } from "../../contracts/DistributionCreator.sol";
import "./Fixture.s.sol";

contract DistributionCreatorOOGTest is Fixture {
    using SafeERC20 for IERC20;

    uint32 startTime;
    uint256 constant maxDistribForOOG = 1e4;

    function setUp() public override {
        super.setUp();

        startTime = uint32(block.timestamp);

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
    }

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
        for (uint256 i; i < maxDistribForOOG + 1; i++) {
            // params.epochStart += uint32(10 * i);
            creator.createDistribution(params);
        }
        vm.stopPrank();

        uint32 endTime = startTime + 25 * EPOCH_DURATION;

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
}
