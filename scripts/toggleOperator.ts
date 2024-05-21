import { deployments, ethers } from 'hardhat';

import { Distributor, Distributor__factory } from '../typechain';
import { registry } from '@angleprotocol/sdk';

const users = [''];
const operators = [''];

async function main() {
  let distributor: Distributor;
  const { deployer } = await ethers.getNamedSigners();
  const chainId = (await deployer.provider?.getNetwork())?.chainId;
  console.log('chainId', chainId);
  const distributorAddress = registry(chainId as unknown as number)?.Merkl?.Distributor; // (await deployments.get('DistributionCreator')).address;

  if (!distributorAddress) {
    throw new Error('Manager address not found');
  }

  distributor = new ethers.Contract(
    distributorAddress,
    Distributor__factory.createInterface(),
    deployer,
  ) as Distributor;

  for (const user of users) {
    for (const operator of operators) {
      if ((await distributor.operators(user, operator)).toString() !== '1') {
        console.log(`Toggling operator ${operator} for user ${user}`);
        const res = await (await distributor.connect(deployer).toggleOperator(user, operator)).wait();
        console.log(res.status);
      } else {
        console.log(`Operator ${operator} is already toggled for user ${user}`);
      }
    }
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
