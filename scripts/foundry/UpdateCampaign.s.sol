// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { DistributionCreator, DistributionParameters, CampaignParameters } from "contracts/DistributionCreator.sol";
import { MockToken, IERC20 } from "contracts/mock/MockToken.sol";
import { CommonUtils, ContractType } from "utils/src/CommonUtils.sol";
import { CHAIN_BASE } from "utils/src/Constants.sol";
import { StdAssertions } from "forge-std/Test.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract UpdateCampaign is CommonUtils, StdAssertions {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        /// TODO: COMPLETE
        uint256 chainId = CHAIN_BASE;
        IERC20 rewardToken = IERC20(0xC011882d0f7672D8942e7fE2248C174eeD640c8f);
        uint256 amount = 97 ether; // after fees
        bytes32 campaignId = 0xba2af37b09cc7627766d25a587bb481cede79c7e7db30ce68ca01f0555cdd828;
        uint32 startTimestamp = uint32(1732191162);
        uint32 duration = 3600 * 10;
        /// END

        DistributionCreator distributionCreator = DistributionCreator(
            _chainToContract(chainId, ContractType.DistributionCreator)
        );
        uint32 timestamp = uint32(block.timestamp);

        // // Do some mint and deposit to change a lot reward distribution
        // vm.startBroadcast(0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776);
        // MockToken(address(0x0000206329b97DB379d5E1Bf586BbDB969C63274)).mint(deployer, 100_000 ether);
        // vm.stopBroadcast();

        vm.startBroadcast(deployer);

        // IERC20(0x0000206329b97DB379d5E1Bf586BbDB969C63274).approve(
        //     address(0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C),
        //     100_000 ether
        // );
        // ERC4626(0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C).deposit(100_000 ether, deployer);

        // // ERC20 distrib change duration
        // uint32 campaignType = 1;
        // bytes memory campaignData = abi.encode(
        //     0xbEEfa1aBfEbE621DF50ceaEF9f54FdB73648c92C,
        //     new address[](0),
        //     new address[](0),
        //     "",
        //     new bytes[](0),
        //     new bytes[](0),
        //     hex""
        // );

        // // ERC20 distrib
        // uint32 campaignType = 1;
        // bytes memory campaignData = abi.encode(
        //     0x70F796946eD919E4Bc6cD506F8dACC45E4539771,
        //     new address[](0),
        //     new address[](0),
        //     "",
        //     new bytes[](0),
        //     new bytes[](0),
        //     hex""
        // );

        // // Silo distrib
        // address[] memory whitelist = new address[](1);
        // whitelist[0] = 0x8095806d8753C0443C118D1C5e5eEC472e30BFeC;
        // uint32 campaignType = 5;
        // bytes memory campaignData = abi.encode(
        //     0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A,
        //     2,
        //     0xa42001D6d2237d2c74108FE360403C4b796B7170,
        //     whitelist,
        //     new address[](0),
        //     hex""
        // );

        // CLAMM distrib
        uint32 campaignType = 2;
        bytes memory campaignData = abi.encode(
            0x5280d5E63b416277d0F81FAe54Bb1e0444cAbDAA,
            5100,
            1700,
            3200,
            false,
            address(0),
            1,
            new address[](0),
            new address[](0),
            "",
            new bytes[](0),
            hex""
        );

        distributionCreator.overrideCampaign(
            campaignId,
            CampaignParameters({
                campaignId: campaignId,
                creator: deployer,
                rewardToken: address(rewardToken),
                amount: amount,
                campaignType: campaignType,
                startTimestamp: startTimestamp,
                duration: duration,
                campaignData: campaignData
            })
        );

        (
            ,
            address campaignCreator,
            address campaignRewardToken,
            uint256 campaignAmount,
            uint256 campaignCampaignType,
            uint32 campaignStartTimestamp,
            uint32 campaignDuration,
            bytes memory campaignCampaignData
        ) = distributionCreator.campaignOverrides(campaignId);
        assertEq(campaignCreator, deployer);
        assertEq(campaignRewardToken, address(rewardToken));
        assertEq(campaignAmount, amount);
        assertEq(campaignCampaignType, campaignType);
        assertEq(campaignStartTimestamp, startTimestamp);
        assertEq(campaignDuration, duration);
        assertEq(campaignCampaignData, campaignData);
        // assertLt(distributionCreator.campaignOverridesTimestamp(campaignId, 0), timestamp);
        // assertLt(distributionCreator.campaignOverridesTimestamp(campaignId, 1), timestamp);
        // assertLt(distributionCreator.campaignOverridesTimestamp(campaignId, 2), timestamp);
        assertGe(distributionCreator.campaignOverridesTimestamp(campaignId, 0), timestamp);
        vm.expectRevert();
        distributionCreator.campaignOverridesTimestamp(campaignId, 1);

        vm.stopBroadcast();
    }
}
