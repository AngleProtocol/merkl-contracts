import { deployments, ethers } from 'hardhat';

import { DistributionCreator, DistributionCreator__factory } from '../typechain';

async function main() {
  const { deployer } = await ethers.getNamedSigners();
  const managerAddress = (await deployments.get('DistributionCreator')).address;
  const manager: DistributionCreator = new ethers.Contract(
    managerAddress,
    DistributionCreator__factory.createInterface(),
    deployer,
  ) as DistributionCreator;

  console.log('Setting fee recipient');
  await manager.setFeeRecipient('0x916685b590233ba10c0b52b3fae6b0e75e9ab477');
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
