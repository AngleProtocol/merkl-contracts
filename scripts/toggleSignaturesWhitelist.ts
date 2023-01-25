import { deployments, ethers } from 'hardhat';

import { MerkleRewardManager, MerkleRewardManager__factory } from '../typechain';

async function main() {
  let manager: MerkleRewardManager;
  const { deployer } = await ethers.getNamedSigners();

  const managerAddress = (await deployments.get('MerkleRewardManager')).address;

  manager = new ethers.Contract(
    managerAddress,
    MerkleRewardManager__factory.createInterface(),
    deployer,
  ) as MerkleRewardManager;

  console.log('Toggling signature whitelist');
  await (await manager.connect(deployer).toggleSigningWhitelist(deployer.address)).wait();
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
