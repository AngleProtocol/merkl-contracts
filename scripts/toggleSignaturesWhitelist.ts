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
  const address = '0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701'
  await (await manager.connect(deployer).toggleSigningWhitelist(address)).wait();
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
