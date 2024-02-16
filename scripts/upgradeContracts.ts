import { ChainId, registry } from '@angleprotocol/sdk';
import { deployments, ethers } from 'hardhat';
import yargs from 'yargs';

import { DistributionCreator, DistributionCreator__factory, Distributor, Distributor__factory } from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

async function main() {
  let manager: DistributionCreator;
  let distributor: Distributor;
  const [deployer] = await ethers.getSigners();

  const distributionAddress = registry(ChainId.MAINNET)?.Merkl?.DistributionCreator!;
  const distributorAddress = registry(ChainId.MAINNET)?.Merkl?.Distributor!;
  console.log(deployer.address);

  manager = new ethers.Contract(
    distributionAddress,
    DistributionCreator__factory.createInterface(),
    deployer,
  ) as DistributionCreator;

  distributor = new ethers.Contract(
    distributorAddress,
    Distributor__factory.createInterface(),
    deployer,
  ) as Distributor;

  const newImplementation = await deployments.get('DistributionCreator_Implementation_V2_0');
  console.log('1st upgrade');
  await manager.connect(deployer).upgradeTo(newImplementation.address);
  const newDistribImplementation = await deployments.get('Distributor_Implementation_V2_0');
  console.log('2nd upgrade');
  await distributor.connect(deployer).upgradeTo(newDistribImplementation.address);

  console.log(await manager.core());
  console.log(await manager.distributor());
  console.log(await manager.feeRecipient());
  console.log((await manager.defaultFees()).toString());
  console.log(await manager.message());
  console.log(await manager.distributionList(1));
  console.log((await manager.feeRebate(deployer.address)).toString());
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
