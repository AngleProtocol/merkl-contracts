import { deployments, ethers } from 'hardhat';

import { DistributionCreator, DistributionCreator__factory } from '../typechain';
import { parseEther,parseUnits } from 'ethers/lib/utils';
import { parseAmount } from '../utils/bignumber';

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
      .setRewardTokenMinAmounts(['0xEdb73D4ED90bE7A49D06d0D940055e6d181d22fa','0xB60acD2057067DC9ed8c083f5aa227a244044fD6'], [parseEther('10'),parseAmount.gwei('0.0015')])
  ).wait();
  // 18 decimals
  // 000000000000000000
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
