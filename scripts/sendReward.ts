import { parseEther } from 'ethers/lib/utils';
import { deployments, ethers, web3 } from 'hardhat';

import { MAX_UINT256, ZERO_ADDRESS } from '../test/hardhat/utils/helpers';
import { MerkleRewardManager, MerkleRewardManager__factory, MockToken, MockToken__factory } from '../typechain';

async function main() {
  let manager: MerkleRewardManager;
  let mockToken: MockToken;
  const { deployer } = await ethers.getNamedSigners();

  const managerAddress = (await deployments.get('MerkleRewardManager')).address;
  const mockTokenAddress = '0x02Cb0586F9252626e992B2C6c1B792d9751f2Ede';
  const uniV3agEURUSDC = '0x3fa147d6309abeb5c1316f7d8a7d8bd023e0cd80';

  manager = new ethers.Contract(
    managerAddress,
    MerkleRewardManager__factory.createInterface(),
    deployer,
  ) as MerkleRewardManager;
  mockToken = new ethers.Contract(mockTokenAddress, MockToken__factory.createInterface(), deployer) as MockToken;

  const params = {
    uniV3Pool: uniV3agEURUSDC,
    token: mockToken.address,
    positionWrappers: [],
    wrapperTypes: [],
    amount: parseEther('1'),
    propToken1: 4000,
    propToken2: 2000,
    propFees: 4000,
    outOfRangeIncentivized: 0,
    // 25th of January at 8pm -> change this
    epochStart: 1674675727,
    numEpoch: 1000,
    boostedReward: 0,
    boostingAddress: ZERO_ADDRESS,
    rewardId: web3.utils.soliditySha3('testing') as string,
  };

  console.log('Approving');
  await (await mockToken.connect(deployer).approve(manager.address, MAX_UINT256)).wait();

  console.log('Depositing reward');
  await (await manager.connect(deployer).depositReward(params)).wait();
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
