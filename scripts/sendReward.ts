import { parseEther } from 'ethers/lib/utils';
import { ethers, web3 } from 'hardhat';

import { ZERO_ADDRESS } from '../test/hardhat/utils/helpers';
import { DistributionCreator__factory } from '../typechain';

async function main() {
  const { deployer } = await ethers.getNamedSigners();

  const distributionCreator = `0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd`;
  const rewardTokenAddress = '0xC16B81Af351BA9e64C1a069E3Ab18c244A1E3049';
  const pool = '0x599a68d45e6eed05aa8c5c0c85e7efeb5086d8e1';

  const manager = DistributionCreator__factory.connect(distributionCreator, deployer);

  const params = {
    uniV3Pool: pool,
    rewardToken: rewardTokenAddress,
    positionWrappers: [],
    wrapperTypes: [0],
    amount: parseEther('1000'),
    propToken0: 1000,
    propToken1: 8000,
    propFees: 1000,
    isOutOfRangeIncentivized: 0,
    epochStart: 1700667000,
    numEpoch: 24 * 2,
    boostedReward: 0,
    boostingAddress: ZERO_ADDRESS,
    rewardId: web3.utils.soliditySha3('') as string,
    additionalData: ethers.utils.defaultAbiCoder.encode(['uint256'], ['0x12']) as string,
  };

  /**
   * Create distribution
   */
  const tx = await manager.connect(deployer).createDistribution(params, { gasLimit: 2_000_000 });
  await tx.wait();
  console.log('...Deposited reward ✅');

  /**
   * Resolve dispute
   */
  // const tx = await distributor.connect(deployer).resolveDispute(true);
  // await tx.wait();

  // const tx = await distributor.connect(deployer).toggleTrusted('0x435046800Fb9149eE65159721A92cB7d50a7534b');
  // await tx.wait();
  // console.log('...Toggled trusted ✅');
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
