import { ChainId, registry } from '@angleprotocol/sdk';
import { deployments, ethers, network, web3 } from 'hardhat';
import yargs from 'yargs';

import { deployUpgradeableUUPS, increaseTime, ZERO_ADDRESS } from '../../test/hardhat/utils/helpers';
import {
  DistributionCreator,
  DistributionCreator__factory,
  Distributor,
  Distributor__factory,
  ERC20,
} from '../../typechain';
import { formatAmount, parseAmount } from '../../utils/bignumber';

const argv = yargs.env('').boolean('ci').parseSync();

async function main() {
  let manager: DistributionCreator;
  let distributor: Distributor;
  let params: any;

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  const governor = registry(ChainId.MAINNET)?.AngleLabs!;

  await network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [governor],
  });
  await network.provider.send('hardhat_setBalance', [governor, '0x10000000000000000000000000000']);
  const governorSigner = await ethers.provider.getSigner(governor);

  const distributionAddress = registry(ChainId.MAINNET)?.Merkl?.DistributionCreator!;
  const distributorAddress = registry(ChainId.MAINNET)?.Merkl?.Distributor!;

  manager = new ethers.Contract(
    distributionAddress,
    DistributionCreator__factory.createInterface(),
    governorSigner,
  ) as DistributionCreator;

  distributor = new ethers.Contract(
    distributorAddress,
    Distributor__factory.createInterface(),
    governorSigner,
  ) as Distributor;

  const newImplementation = await new DistributionCreator__factory(deployer).deploy();
  await manager.connect(governorSigner).upgradeTo(newImplementation.address);
  const newDistribImplementation = await new Distributor__factory(deployer).deploy();
  await distributor.connect(governorSigner).upgradeTo(newDistribImplementation.address);

  console.log(await manager.core());
  console.log(await manager.distributor());
  console.log(await manager.feeRecipient());
  console.log((await manager.defaultFees()).toString());
  console.log(await manager.message());
  console.log(await manager.distributionList(10));
  console.log((await manager.feeRebate(governor)).toString());
  console.log((await manager.isWhitelistedToken(registry(ChainId.MAINNET)?.agEUR?.AgToken!)).toString());
  console.log((await manager._nonces('0xfda462548ce04282f4b6d6619823a7c64fdc0185')).toString());
  console.log((await manager.userSignatureWhitelist('0xfda462548ce04282f4b6d6619823a7c64fdc0185')).toString());
  console.log(await manager.rewardTokens(0));
  // console.log(await manager.campaignList(0));
  console.log((await manager.campaignSpecificFees(0)).toString());

  console.log(await distributor.tree());
  console.log(await distributor.lastTree());
  console.log(await distributor.disputeToken());
  console.log(await distributor.core());
  console.log(await distributor.disputer());
  console.log((await distributor.endOfDisputePeriod()).toString());
  console.log((await distributor.disputePeriod()).toString());
  console.log((await distributor.disputeAmount()).toString());
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
