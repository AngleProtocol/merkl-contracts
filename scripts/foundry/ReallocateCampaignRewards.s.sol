// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { DistributionCreator, DistributionParameters, CampaignParameters } from "contracts/DistributionCreator.sol";
import { MockToken, IERC20 } from "contracts/mock/MockToken.sol";
import { CommonUtils, ContractType } from "utils/src/CommonUtils.sol";
import { CHAIN_BASE } from "utils/src/Constants.sol";
import { StdAssertions } from "forge-std/Test.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract ReallocateCampaignRewards is CommonUtils, StdAssertions {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        /// TODO: COMPLETE
        uint256 chainId = CHAIN_BASE;
        IERC20 rewardToken = IERC20(0xC011882d0f7672D8942e7fE2248C174eeD640c8f);
        uint256 amount = 97 ether; // after fees
        bytes32 campaignId = 0x1d1231a7a6958431a5760b929c56f0e44a20f06e92a52324c19a2e4d2ec529bc;
        address to = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        address[] memory froms = new address[](2);
        froms[0] = 0x15775b23340C0f50E0428D674478B0e9D3D0a759;
        froms[1] = 0xe4BB74804edf5280c9203f034036f7CB15196078;
        /// END

        DistributionCreator distributionCreator = DistributionCreator(
            _chainToContract(chainId, ContractType.DistributionCreator)
        );
        uint32 timestamp = uint32(block.timestamp);

        vm.startBroadcast(deployer);

        distributionCreator.reallocateCampaignRewards(campaignId, froms, to);

        assertEq(distributionCreator.campaignReallocation(campaignId, froms[0]), to);
        assertEq(distributionCreator.campaignListReallocation(campaignId, 0), froms[0]);
        assertEq(distributionCreator.campaignListReallocation(campaignId, 1), froms[1]);

        vm.stopBroadcast();
    }
}
