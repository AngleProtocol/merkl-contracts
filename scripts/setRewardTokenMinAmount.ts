import { deployments, ethers } from 'hardhat';

import { DistributionCreator, DistributionCreator__factory } from '../typechain';
import { parseEther,parseUnits, getAddress } from 'ethers/lib/utils';
import { registry } from '@angleprotocol/sdk';

async function main() {
  let manager: DistributionCreator;
  const { deployer } = await ethers.getNamedSigners();
  const chainId = (await deployer.provider?.getNetwork())?.chainId;
  console.log('chainId', chainId)
  const managerAddress = registry(chainId as unknown as number)?.Merkl?.DistributionCreator // (await deployments.get('DistributionCreator')).address;

  if (!managerAddress) {
    throw new Error('Manager address not found');
  }

  manager = new ethers.Contract(
    managerAddress,
    DistributionCreator__factory.createInterface(),
    deployer,
  ) as DistributionCreator;

  console.log('Setting reward token min amount');
  
  const token = {
    address: '',
    decimals: 0,
    minAmount: '0',
  }

  const res = await (
    await manager
      .connect(deployer)
      .setRewardTokenMinAmounts([getAddress(token.address)], [parseUnits(token.minAmount, token.decimals)])
  ).wait();
  
  console.log(res);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
