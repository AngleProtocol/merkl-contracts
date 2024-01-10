// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { DistributionParameters, ExtensiveDistributionParameters } from "../../contracts/DistributionCreator.sol";
import "./Fixture.t.sol";

contract DistributionCreatorOOGTest is Fixture {
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

    function testFuzz_getActiveDistributions() public {
        uint256 lastIndexDistribution;
        {
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getActivePoolDistributions(address(pool), 0, 1);
            ExtensiveDistributionParameters[] memory searchDistributions;
            (searchDistributions, lastIndexDistribution) = creator.getActiveDistributions(0, 1);
            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(lastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, 1);
            // The first distribution is finsihed
            assertEq(lastIndexDistribution, 2);
            assertEq(searchDistributions[0].base.rewardId, bytes32(keccak256(abi.encodePacked(alice, uint256(1)))));
        }

        uint32 first = 2;
        lastIndexDistribution = 2;
        for (uint i; i < nbrDistrib / first; i++) {
            {
                (
                    ExtensiveDistributionParameters[] memory searchDistributionsPool,
                    uint256 lastIndexDistributionPool
                ) = creator.getActivePoolDistributions(address(pool), uint32(lastIndexDistribution), first);
                ExtensiveDistributionParameters[] memory searchDistributions;
                (searchDistributions, lastIndexDistribution) = creator.getActiveDistributions(
                    uint32(lastIndexDistribution),
                    first
                );
                assertEq(searchDistributions.length, searchDistributionsPool.length);
                assertEq(lastIndexDistribution, lastIndexDistributionPool);
                assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

                assertEq(searchDistributions.length, (i != nbrDistrib / first - 1) ? first : first - 1);
                assertEq(
                    lastIndexDistribution,
                    (i != nbrDistrib / first - 1) ? 2 + (i + 1) * first : 2 + (i + 1) * first - 1
                );
                assertEq(
                    searchDistributions[0].base.rewardId,
                    bytes32(keccak256(abi.encodePacked(alice, uint256(2 + i * first))))
                );
            }
        }
    }

    function testFuzz_getDistributionsForEpoch() public {
        uint256 lastIndexDistribution;
        {
            ExtensiveDistributionParameters[] memory searchDistributions;
            (searchDistributions, lastIndexDistribution) = creator.getDistributionsForEpoch(initStartTime, 0, 1);
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getPoolDistributionsForEpoch(address(pool), initStartTime, 0, 1);
            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(lastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, 1);
            // The first distribution is finsihed
            assertEq(lastIndexDistribution, 1);
            assertEq(searchDistributions[0].base.rewardId, bytes32(keccak256(abi.encodePacked(alice, uint256(0)))));
        }

        uint32 first = 2;
        lastIndexDistribution = 6;
        {
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getPoolDistributionsForEpoch(address(pool), startTime, uint32(lastIndexDistribution), first);
            (ExtensiveDistributionParameters[] memory searchDistributions, uint256 endLastIndexDistribution) = creator
                .getDistributionsForEpoch(startTime, uint32(lastIndexDistribution), first);
            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(endLastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, first);
            assertEq(endLastIndexDistribution, lastIndexDistribution + first);
            assertEq(
                searchDistributions[0].base.rewardId,
                bytes32(keccak256(abi.encodePacked(alice, lastIndexDistribution)))
            );
        }
    }

    function testFuzz_getDistributionsBetweenEpochs() public {
        uint256 lastIndexDistribution;
        {
            ExtensiveDistributionParameters[] memory searchDistributions;
            (searchDistributions, lastIndexDistribution) = creator.getDistributionsBetweenEpochs(
                initStartTime,
                startTime + 1,
                0,
                100
            );
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getPoolDistributionsBetweenEpochs(address(pool), initStartTime, startTime + 1, 0, 100);
            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(lastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, 1);
            // The first distribution is finsihed
            assertEq(lastIndexDistribution, 11);
            assertEq(searchDistributions[0].base.rewardId, bytes32(keccak256(abi.encodePacked(alice, uint256(0)))));
        }

        uint32 first = 2;
        lastIndexDistribution = 6;
        {
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getPoolDistributionsBetweenEpochs(
                    address(pool),
                    startTime,
                    endTime + 2,
                    uint32(lastIndexDistribution),
                    first
                );
            (ExtensiveDistributionParameters[] memory searchDistributions, uint256 endLastIndexDistribution) = creator
                .getDistributionsBetweenEpochs(startTime, endTime + 2, uint32(lastIndexDistribution), first);

            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(endLastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, first);
            assertEq(endLastIndexDistribution, lastIndexDistribution + first);
            assertEq(
                searchDistributions[0].base.rewardId,
                bytes32(keccak256(abi.encodePacked(alice, lastIndexDistribution)))
            );
        }
    }

    function testFuzz_getDistributionsAfterEpoch() public {
        uint256 lastIndexDistribution;
        {
            ExtensiveDistributionParameters[] memory searchDistributions;
            (searchDistributions, lastIndexDistribution) = creator.getDistributionsAfterEpoch(initStartTime, 0, 100);
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getPoolDistributionsAfterEpoch(address(pool), initStartTime, 0, 100);
            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(lastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, 11);
            // The first distribution is finsihed
            assertEq(lastIndexDistribution, 11);
            assertEq(searchDistributions[0].base.rewardId, bytes32(keccak256(abi.encodePacked(alice, uint256(0)))));
        }

        {
            ExtensiveDistributionParameters[] memory searchDistributions;
            (searchDistributions, lastIndexDistribution) = creator.getDistributionsAfterEpoch(startTime, 0, 100);
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getPoolDistributionsAfterEpoch(address(pool), startTime, 0, 100);
            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(lastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, 10);
            // The first distribution is finsihed
            assertEq(lastIndexDistribution, 11);
            assertEq(searchDistributions[0].base.rewardId, bytes32(keccak256(abi.encodePacked(alice, uint256(1)))));
        }

        uint32 first = 3;
        lastIndexDistribution = 5;
        {
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getPoolDistributionsAfterEpoch(
                    address(pool),
                    initStartTime,
                    uint32(lastIndexDistribution),
                    first
                );
            (ExtensiveDistributionParameters[] memory searchDistributions, uint256 endLastIndexDistribution) = creator
                .getDistributionsAfterEpoch(initStartTime, uint32(lastIndexDistribution), first);

            assertEq(searchDistributions.length, searchDistributionsPool.length);
            assertEq(endLastIndexDistribution, lastIndexDistributionPool);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, first);
            assertEq(endLastIndexDistribution, lastIndexDistribution + first);
            assertEq(
                searchDistributions[0].base.rewardId,
                bytes32(keccak256(abi.encodePacked(alice, lastIndexDistribution)))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 WITH DIFFERENT POOLS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    function testFuzz_getActiveDistributionsWithDifferentPool() public {
        address[] memory positionWrappers = new address[](3);
        uint32[] memory wrapperTypes = new uint32[](3);
        positionWrappers[0] = alice;
        positionWrappers[1] = bob;
        positionWrappers[2] = charlie;
        wrapperTypes[0] = 0;
        wrapperTypes[1] = 1;
        wrapperTypes[2] = 2;

        MockUniswapV3Pool pool2 = new MockUniswapV3Pool();
        pool2.setToken(address(token0), 0);
        pool2.setToken(address(token1), 1);

        vm.startPrank(alice);
        DistributionParameters memory params = DistributionParameters({
            uniV3Pool: address(pool2),
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

        for (uint256 i; i < 4; i++) creator.createDistribution(params);

        vm.stopPrank();

        uint32 first = 5;
        uint256 lastIndexDistribution = 8;
        {
            (
                ExtensiveDistributionParameters[] memory searchDistributionsPool,
                uint256 lastIndexDistributionPool
            ) = creator.getActivePoolDistributions(address(pool), uint32(lastIndexDistribution), first);
            ExtensiveDistributionParameters[] memory searchDistributions;
            (searchDistributions, lastIndexDistribution) = creator.getActiveDistributions(
                uint32(lastIndexDistribution),
                first
            );
            assertEq(searchDistributionsPool.length, 3);
            assertEq(lastIndexDistributionPool, 15);
            assertEq(searchDistributions[0].base.rewardId, searchDistributionsPool[0].base.rewardId);

            assertEq(searchDistributions.length, first);
            assertEq(lastIndexDistribution, 13);
            assertEq(
                searchDistributions[0].base.rewardId,
                bytes32(keccak256(abi.encodePacked(alice, uint256(lastIndexDistribution - first))))
            );
            assertEq(searchDistributions[0].base.uniV3Pool, address(pool));
        }
    }
}
