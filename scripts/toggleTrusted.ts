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

  console.log('Toggling trusted');
  await manager.toggleTrusted('0x435046800Fb9149eE65159721A92cB7d50a7534b');
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
