import { deployments, ethers } from 'hardhat';

import { DistributionCreator, DistributionCreator__factory } from '../typechain';

async function main() {
  let manager: DistributionCreator;
  const { deployer } = await ethers.getNamedSigners();
  const managerAddress = (await deployments.get('DistributionCreator')).address;

  manager = new ethers.Contract(
    managerAddress,
    DistributionCreator__factory.createInterface(),
    deployer,
  ) as DistributionCreator;

  console.log('Setting reward token min amount');
  await (
    await manager
      .connect(deployer)
      .setRewardTokenMinAmounts(['0x0D1E753a25eBda689453309112904807625bEFBe'], [200000000000000000000000])
  ).wait();
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
