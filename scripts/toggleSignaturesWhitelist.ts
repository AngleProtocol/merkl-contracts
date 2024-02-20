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

  console.log('Toggling signature whitelist');
  const address = '0xd818b9f7cb4090047d26c51e63c9cb1b5e12886a'
  await (await manager.connect(deployer).toggleSigningWhitelist(address)).wait();
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
