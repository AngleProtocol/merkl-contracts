// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { DistributionCreator, DistributionParameters, CampaignParameters } from "contracts/DistributionCreator.sol";
import { MockToken, IERC20 } from "contracts/mock/MockToken.sol";
import { CommonUtils, ContractType } from "utils/src/CommonUtils.sol";
import { CHAIN_BASE } from "utils/src/Constants.sol";
import { StdAssertions } from "forge-std/Test.sol";

contract CreateCampaign is CommonUtils, StdAssertions {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        /// TODO: COMPLETE
        uint256 chainId = CHAIN_BASE;
        IERC20 rewardToken = IERC20(0xC011882d0f7672D8942e7fE2248C174eeD640c8f);
        uint256 amount = 100 ether;
        /// END

        DistributionCreator distributionCreator = DistributionCreator(
            _chainToContract(chainId, ContractType.DistributionCreator)
        );

        vm.startBroadcast(deployer);

        MockToken(address(rewardToken)).mint(deployer, amount);
        rewardToken.approve(address(distributionCreator), amount);
        uint32 startTimestamp = uint32(block.timestamp + 600);
        bytes32 campaignId = distributionCreator.createCampaign(
            CampaignParameters({
                campaignId: bytes32(0),
                creator: deployer,
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

        CampaignParameters memory campaign = distributionCreator.campaign(campaignId);
        assertEq(campaign.creator, deployer);
        assertEq(campaign.rewardToken, address(rewardToken));
        assertEq(campaign.amount, (amount * (1e9 - distributionCreator.defaultFees())) / 1e9);
        assertEq(campaign.campaignType, 1);
        assertEq(campaign.startTimestamp, startTimestamp);
        assertEq(campaign.duration, 3600 * 24);

        vm.stopBroadcast();
    }
}
