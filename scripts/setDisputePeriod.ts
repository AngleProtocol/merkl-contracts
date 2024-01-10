import { deployments, ethers } from 'hardhat';

import { Distributor, Distributor__factory } from '../typechain';

async function main() {
  const { deployer } = await ethers.getNamedSigners();
  const managerAddress = (await deployments.get('Distributor')).address;
  const manager: Distributor = new ethers.Contract(
    managerAddress,
    Distributor__factory.createInterface(),
    deployer,
  ) as Distributor;

  console.log('Setting dispute period');
  await manager.setDisputePeriod(1);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
