import { deployments, ethers } from 'hardhat';

import { DistributionCreator, MerkleRewardManager__factory } from '../typechain';

async function main() {
  let manager: DistributionCreator;
  const { deployer } = await ethers.getNamedSigners();

  const managerAddress = (await deployments.get('DistributionCreator')).address;

  manager = new ethers.Contract(
    managerAddress,
    MerkleRewardManager__factory.createInterface(),
    deployer,
  ) as DistributionCreator;

  console.log('Toggling signature whitelist');
  await (await manager.connect(deployer).toggleSigningWhitelist(deployer.address)).wait();
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
