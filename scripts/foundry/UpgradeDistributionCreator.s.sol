// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { DistributionCreator, DistributionParameters, CampaignParameters } from "contracts/DistributionCreator.sol";
import { CommonUtils, ContractType } from "utils/src/CommonUtils.sol";
import { CHAIN_BASE } from "utils/src/Constants.sol";
import { StdAssertions } from "forge-std/Test.sol";

contract UpgradeDistributionCreator is CommonUtils, StdAssertions {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        /// TODO: COMPLETE
        uint256 chainId = CHAIN_BASE;
        /// END

        DistributionCreator distributionCreator = DistributionCreator(
            _chainToContract(chainId, ContractType.DistributionCreator)
        );
        address governor = _chainToContract(chainId, ContractType.AngleLabsMultisig);

        vm.startBroadcast(deployer);
        // We deploy the new implementation
        address creatorImpl = address(new DistributionCreator());
        vm.stopBroadcast();

        // Upgrade
        vm.startBroadcast(governor);
        distributionCreator.upgradeTo(address(creatorImpl));
        vm.stopBroadcast();

        // Test storage
        assertEq(address(distributionCreator.core()), _chainToContract(chainId, ContractType.CoreMerkl));
        assertEq(address(distributionCreator.distributor()), _chainToContract(chainId, ContractType.Distributor));
        assertEq(distributionCreator.defaultFees(), 0.03e9);
        assertEq(
            distributionCreator.message(),
            '" 1. Merkl is experimental software provided as is, use it at your own discretion. There may notably be delays in the onchain Merkle root updates and there may be flaws in the script (or engine) or in the infrastructure used to update results onchain. In that regard, everyone can permissionlessly dispute the rewards which are posted onchain, and when creating a distribution, you are responsible for checking the results and eventually dispute them. 2. If you are specifying an invalid pool address or a pool from an AMM that is not marked as supported, your rewards will not be taken into account and you will not be able to recover them. 3. If you do not blacklist liquidity position managers or smart contract addresses holding LP tokens that are not natively supported by the Merkl system, or if you don\'t specify the addresses of the liquidity position managers that are not automatically handled by the system, then the script will not be able to take the specifities of these addresses into account, and it will reward them like a normal externally owned account would be. If these are smart contracts that do not support external rewards, then rewards that should be accruing to it will be lost. 4. If rewards sent through Merkl remain unclaimed for a period of more than 1 year after the end of the distribution (because they are meant for instance for smart contract addresses that cannot claim or deal with them), then we reserve the right to recover these rewards. 5. Fees apply to incentives deposited on Merkl, unless the pools incentivized contain a whitelisted token (e.g an Angle Protocol stablecoin). 6. By interacting with the Merkl smart contract to deposit an incentive for a pool, you are exposed to smart contract risk and to the offchain mechanism used to compute reward distribution. 7. If the rewards you are sending are too small in value, or if you are sending rewards using a token that is not approved for it, your rewards will not be handled by the script, and they may be lost. 8. If you mistakenly send too much rewards compared with what you wanted to send, you will not be able to call them back. You will also not be able to prematurely end a reward distribution once created. 9. The engine handling reward distribution for a pool may not look at all the swaps occurring on the pool during the time for which you are incentivizing, but just at a subset of it to gain in efficiency. Overall, if you distribute incentives using Merkl, it means that you are aware of how the engine works, of the approximations it makes and of the behaviors it may trigger (e.g. just in time liquidity). 10. Rewards corresponding to incentives distributed through Merkl do not compound block by block, but are regularly made available (through a Merkle root update) at a frequency which depends on the chain. "'
        );
        assertEq(distributionCreator.messageHash(), 0x08dabc24dcfcb230453d08bce47c730ed6f1cce205bc153680488959b503644e);
        {
            (bytes32 campaignId, , , , , , , , , , , , ) = distributionCreator.distributionList(0);
            assertEq(campaignId, 0xb3fc2abc303c70a16ab9d5fc38d7e8aeae66593a87a3d971b024dd34b97e94b1);
        }
        {
            (bytes32 campaignId, , , , , , , , , , , , ) = distributionCreator.distributionList(73);
            assertEq(campaignId, 0x157a32c11ce34030465e1c28c309f38c18161028355f3446f54b677d11ceb63a);
        }
        assertEq(distributionCreator.feeRebate(0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185), 0);
        assertEq(distributionCreator.isWhitelistedToken(_chainToContract(chainId, ContractType.AgEUR)), 1);
        assertEq(distributionCreator._nonces(0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185), 4);
        assertEq(
            distributionCreator.userSignatures(0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185),
            0x08dabc24dcfcb230453d08bce47c730ed6f1cce205bc153680488959b503644e
        );
        assertEq(distributionCreator.userSignatureWhitelist(0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185), 0);

        assertEq(distributionCreator.rewardTokens(0), 0x7D49a065D17d6d4a55dc13649901fdBB98B2AFBA);
        assertEq(distributionCreator.rewardTokens(21), 0xF734eFdE0C424BA2B547b186586dE417b0954802);
        assertEq(distributionCreator.rewardTokenMinAmounts(0x7D49a065D17d6d4a55dc13649901fdBB98B2AFBA), 1 ether);

        {
            (bytes32 campaignId, , , , , , , ) = distributionCreator.campaignList(0);
            assertEq(campaignId, 0x4e2bf13f682a244a80e0f25e1545fc8ad3a181d60658d22a3d347ee493e2a740);
        }
        {
            (bytes32 campaignId, , , , , , , ) = distributionCreator.campaignList(67);
            assertEq(campaignId, 0xf7d416acc480a41cd4cbb1bd68941f2f585adb659bd95d45e193589175356972);
        }
        assertEq(distributionCreator.campaignSpecificFees(4), 0.005e9);

        {
            (bytes32 campaignId, , , , , , , ) = distributionCreator.campaignOverrides(
                0xf7d416acc480a41cd4cbb1bd68941f2f585adb659bd95d45e193589175356972
            );
            assertEq(campaignId, bytes32(0));
        }

        vm.expectRevert();
        distributionCreator.campaignOverridesTimestamp(
            0x4e2bf13f682a244a80e0f25e1545fc8ad3a181d60658d22a3d347ee493e2a740,
            0
        );
    }
}
