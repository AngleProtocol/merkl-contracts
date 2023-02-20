import { parseEther } from 'ethers/lib/utils';
import { ethers, web3 } from 'hardhat';

import { ZERO_ADDRESS } from '../test/hardhat/utils/helpers';
import { DistributionCreator__factory, MockCoreBorrow__factory } from '../typechain';

async function main() {
  const { deployer } = await ethers.getNamedSigners();

  const distributorCreator = `0xA9c076992F3917b47E2C619c46ff0b652d76e6B4`;
  const mockTokenAddress = '0x84FB94595f9Aef81147cD4070a1564128A84bb7c';
  const pool = '0x3fa147d6309abeb5c1316f7d8a7d8bd023e0cd80';

  const manager = DistributionCreator__factory.connect(distributorCreator, deployer);
  const mockToken = MockCoreBorrow__factory.connect(mockTokenAddress, deployer);

  const params = {
    uniV3Pool: pool,
    rewardToken: mockToken.address,
    positionWrappers: ['0x1644de0A8E54626b54AC77463900FcFFD8B94542', '0xa29193Af0816D43cF44A3745755BF5f5e2f4F170'],
    wrapperTypes: [0, 2],
    amount: parseEther('350'),
    propToken0: 4000,
    propToken1: 2000,
    propFees: 4000,
    isOutOfRangeIncentivized: 0,
    epochStart: 1676649600,
    numEpoch: 500,
    boostedReward: 0,
    boostingAddress: ZERO_ADDRESS,
    rewardId: web3.utils.soliditySha3('europtimism') as string,
    additionalData: web3.utils.soliditySha3('europtimism') as string,
  };

  // console.log('Approving');
  // await (await mockToken.connect(deployer).approve(manager.address, MAX_UINT256)).wait();

  console.log('Depositing reward...');
  await (await manager.connect(deployer).createDistribution(params, { gasLimit: 1e6 })).wait();
  console.log('...Deposited reward ✅');
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
