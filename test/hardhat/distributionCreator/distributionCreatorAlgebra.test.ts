import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { parseEther, solidityKeccak256 } from 'ethers/lib/utils';
import hre, { contract, ethers, web3 } from 'hardhat';

import {
  DistributionCreator,
  DistributionCreator__factory,
  MockCoreBorrow,
  MockCoreBorrow__factory,
  MockPool,
  MockPool__factory,
  MockToken,
  MockToken__factory,
} from '../../../typechain';
import { parseAmount } from '../../../utils/bignumber';
import { deployUpgradeableUUPS, latestTime, MAX_UINT256, ZERO_ADDRESS } from '../utils/helpers';

contract('DistributionCreator - Algebra', () => {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let governor: SignerWithAddress;
  let guardian: SignerWithAddress;
  let mockPool: MockPool;
  let angle: MockToken;
  let pool: string;

  let token0: MockToken;
  let token1: MockToken;

  let manager: DistributionCreator;
  let core: MockCoreBorrow;
  let startTime: number;
  // eslint-disable-next-line
  let params: any;

  beforeEach(async () => {
    await hre.network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: process.env.ETH_NODE_URI_ARBITRUM,

            blockNumber: 93300851,
          },
        },
      ],
    });
    [deployer, alice, bob, governor, guardian] = await ethers.getSigners();
    angle = (await new MockToken__factory(deployer).deploy('ANGLE', 'ANGLE', 18)) as MockToken;
    core = (await new MockCoreBorrow__factory(deployer).deploy()) as MockCoreBorrow;

    token0 = (await new MockToken__factory(deployer).deploy('token0', 'token0', 18)) as MockToken;
    token1 = (await new MockToken__factory(deployer).deploy('token1', 'token1', 18)) as MockToken;
    // Algebra pool on Zyberswap/Arbitrum
    pool = '0x308C5B91F63307439FDB51a9fA4Dfc979E2ED6B0';
    mockPool = (await new MockPool__factory(deployer).deploy()) as MockPool;
    await mockPool.setToken(token0.address, 0);
    await mockPool.setToken(token1.address, 1);
    await core.toggleGuardian(guardian.address);
    await core.toggleGovernor(governor.address);
    manager = (await deployUpgradeableUUPS(new DistributionCreator__factory(deployer))) as DistributionCreator;
    await manager.initialize(core.address, bob.address, parseAmount.gwei('0.1'));
    startTime = (await latestTime()) + 1000;
    params = {
      uniV3Pool: pool,
      rewardToken: angle.address,
      positionWrappers: [alice.address, bob.address, deployer.address],
      wrapperTypes: [0, 1, 2],
      amount: parseEther('1'),
      propToken0: 4000,
      propToken1: 2000,
      propFees: 4000,
      isOutOfRangeIncentivized: 0,
      epochStart: startTime,
      numEpoch: 1,
      boostedReward: 0,
      boostingAddress: ZERO_ADDRESS,
      rewardId: web3.utils.soliditySha3('TEST') as string,
      additionalData: web3.utils.soliditySha3('test2ng') as string,
    };
    await angle.mint(alice.address, parseEther('1000'));
    await angle.connect(alice).approve(manager.address, MAX_UINT256);
    await manager.connect(guardian).toggleSigningWhitelist(alice.address);
    await manager.connect(guardian).setRewardTokenMinAmounts([angle.address], [1]);
    await manager.connect(guardian).toggleSigningWhitelist(alice.address);
  });
  describe('createDistribution', () => {
    it('success - has not signed but no message to sign', async () => {
      await manager.connect(alice).createDistribution(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.distributionList(0);
      expect(reward.uniV3Pool).to.be.equal(pool);
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.propToken0).to.be.equal(4000);
      expect(reward.propToken1).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.isOutOfRangeIncentivized).to.be.equal(0);
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      expect(reward.additionalData).to.be.equal(web3.utils.soliditySha3('test2ng'));
      const rewardId = solidityKeccak256(['address', 'uint256'], [alice.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);
      const activeDistributions = await manager['getActiveDistributions()'];
      expect(activeDistributions.length).to.be.equal(0);
      const distributions = await manager['getDistributionsAfterEpoch(uint32)'](reward.epochStart - 1);
      expect(distributions[0].poolFee).to.be.equal(0);
    });
    it('success - on a pool that does not have a fee in it', async () => {
      const params2 = {
        uniV3Pool: mockPool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 1, 2],
        amount: parseEther('1'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      await manager.connect(alice).createDistribution(params2);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.distributionList(0);
      expect(reward.uniV3Pool).to.be.equal(mockPool.address);
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.propToken0).to.be.equal(4000);
      expect(reward.propToken1).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.isOutOfRangeIncentivized).to.be.equal(0);
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      expect(reward.additionalData).to.be.equal(web3.utils.soliditySha3('test2ng'));
      const rewardId = solidityKeccak256(['address', 'uint256'], [alice.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);
      const activeDistributions = await manager['getActiveDistributions()'];
      expect(activeDistributions.length).to.be.equal(0);
      const distributions = await manager['getDistributionsAfterEpoch(uint32)'](reward.epochStart - 1);
      expect(distributions[0].poolFee).to.be.equal(0);
    });
  });
});
