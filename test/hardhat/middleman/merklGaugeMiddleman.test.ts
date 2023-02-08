import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { parseEther, solidityKeccak256 } from 'ethers/lib/utils';
import { contract, ethers, web3 } from 'hardhat';

import {
  DistributionCreator,
  DistributionCreator__factory,
  MockCoreBorrow,
  MockCoreBorrow__factory,
  MockMerklGaugeMiddleman,
  MockMerklGaugeMiddleman__factory,
  MockToken,
  MockToken__factory,
  MockUniswapV3Pool,
  MockUniswapV3Pool__factory,
} from '../../../typechain';
import { parseAmount } from '../../../utils/bignumber';
import { inReceipt } from '../utils/expectEvent';
import { deployUpgradeableUUPS, latestTime, MAX_UINT256, ZERO_ADDRESS } from '../utils/helpers';

contract('DistributionCreator', () => {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let governor: SignerWithAddress;
  let guardian: SignerWithAddress;
  let angle: MockToken;
  let pool: MockUniswapV3Pool;
  let agEUR: string;

  let manager: DistributionCreator;
  let middleman: MockMerklGaugeMiddleman;
  let coreBorrow: MockCoreBorrow;
  let startTime: number;
  // eslint-disable-next-line
  let params: any;

  beforeEach(async () => {
    [deployer, alice, bob, governor, guardian] = await ethers.getSigners();
    angle = (await new MockToken__factory(deployer).deploy('ANGLE', 'ANGLE', 18)) as MockToken;
    coreBorrow = (await new MockCoreBorrow__factory(deployer).deploy()) as MockCoreBorrow;
    pool = (await new MockUniswapV3Pool__factory(deployer).deploy()) as MockUniswapV3Pool;
    middleman = (await new MockMerklGaugeMiddleman__factory(deployer).deploy(
      coreBorrow.address,
    )) as MockMerklGaugeMiddleman;
    await coreBorrow.toggleGuardian(guardian.address);
    await coreBorrow.toggleGovernor(governor.address);
    manager = (await deployUpgradeableUUPS(new DistributionCreator__factory(deployer))) as DistributionCreator;
    await manager.initialize(coreBorrow.address, bob.address, parseAmount.gwei('0.1'));
    startTime = await latestTime();
    params = {
      uniV3Pool: pool.address,
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
    agEUR = '0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8';
    await angle.mint(alice.address, parseEther('1000'));
    await angle.connect(alice).approve(middleman.address, MAX_UINT256);
    await manager.connect(guardian).toggleTokenWhitelist(agEUR);
    await manager.connect(guardian).toggleSigningWhitelist(middleman.address);
    await middleman.setAddresses(alice.address, angle.address, manager.address);
    await middleman.setAngleAllowance();
  });

  describe('initializer', () => {
    it('success - values initialized', async () => {
      expect(await middleman.coreBorrow()).to.be.equal(coreBorrow.address);
      expect(await angle.allowance(middleman.address, manager.address)).to.be.equal(MAX_UINT256);
    });
    it('reverts - zero address', async () => {
      await expect(new MockMerklGaugeMiddleman__factory(deployer).deploy(ZERO_ADDRESS)).to.be.revertedWithCustomError(
        middleman,
        'ZeroAddress',
      );
    });
  });
  describe('setGauge', () => {
    it('reverts - access control', async () => {
      await expect(middleman.connect(alice).setGauge(ZERO_ADDRESS, params)).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
    });
    it('reverts - invalid params', async () => {
      const params0 = {
        uniV3Pool: pool.address,
        rewardToken: agEUR,
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
      const params1 = {
        uniV3Pool: alice.address,
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
      await expect(middleman.connect(guardian).setGauge(ZERO_ADDRESS, params)).to.be.revertedWithCustomError(
        middleman,
        'InvalidParams',
      );
      await expect(middleman.connect(guardian).setGauge(alice.address, params0)).to.be.revertedWithCustomError(
        middleman,
        'InvalidParams',
      );
      // Pool does not have valid tokens 0 and 1
      await expect(middleman.connect(guardian).setGauge(alice.address, params)).to.be.revertedWithCustomError(
        middleman,
        'InvalidParams',
      );
      await expect(middleman.connect(guardian).setGauge(bob.address, params1)).to.be.reverted;
    });
    it('success - value updated - token 0', async () => {
      await pool.setToken(agEUR, 0);
      const receipt = await (await middleman.connect(guardian).setGauge(alice.address, params)).wait();
      inReceipt(receipt, 'GaugeSet', {
        gauge: alice.address,
      });
      const reward = await middleman.gaugeParams(alice.address);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('1'));
      expect(reward.propToken0).to.be.equal(4000);
      expect(reward.propToken1).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.isOutOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(startTime);
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      expect(reward.rewardId).to.be.equal(web3.utils.soliditySha3('TEST') as string);
    });
    it('success - value updated - token 1', async () => {
      await pool.setToken(agEUR, 1);
      const receipt = await (await middleman.connect(guardian).setGauge(alice.address, params)).wait();
      inReceipt(receipt, 'GaugeSet', {
        gauge: alice.address,
      });
      const reward = await middleman.gaugeParams(alice.address);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('1'));
      expect(reward.propToken0).to.be.equal(4000);
      expect(reward.propToken1).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.isOutOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(startTime);
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      expect(reward.rewardId).to.be.equal(web3.utils.soliditySha3('TEST') as string);
    });
  });
  describe('notifyReward', () => {
    it('reverts - invalid params', async () => {
      await pool.setToken(agEUR, 1);
      await middleman.connect(guardian).setGauge(alice.address, params);
      await expect(middleman.connect(bob).notifyReward(ZERO_ADDRESS, parseEther('0.5'))).to.be.revertedWithCustomError(
        middleman,
        'InvalidParams',
      );
      await expect(
        middleman.connect(alice).notifyReward(ZERO_ADDRESS, parseEther('0.5')),
      ).to.be.revertedWithCustomError(middleman, 'InvalidParams');
    });
    it('success - rewards well sent', async () => {
      await pool.setToken(agEUR, 1);
      await middleman.connect(guardian).setGauge(alice.address, params);
      await angle.connect(alice).transfer(middleman.address, parseEther('0.7'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('0.7'));
      await middleman.connect(alice).notifyReward(alice.address, parseEther('0.7'));
      expect(await manager.nonces(middleman.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.7'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('999.3'));
      const reward = await manager.distributionList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.7'));
      expect(reward.propToken0).to.be.equal(4000);
      expect(reward.propToken1).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.isOutOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(await latestTime()));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      const rewardId = solidityKeccak256(['address', 'uint256'], [middleman.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);
    });
    it('success - rewards sent for different gauges at once', async () => {
      const params0 = {
        uniV3Pool: pool.address,
        rewardToken: angle.address,
        positionWrappers: [],
        wrapperTypes: [],
        amount: parseEther('1'),
        propToken0: 3000,
        propToken1: 2000,
        propFees: 5000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 10,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      await pool.setToken(agEUR, 1);
      await middleman.connect(guardian).setGauge(alice.address, params);
      await middleman.connect(guardian).setGauge(bob.address, params0);
      await angle.connect(alice).transfer(middleman.address, parseEther('0.7'));
      await middleman.connect(alice).notifyReward(alice.address, parseEther('0.7'));
      await angle.connect(alice).transfer(middleman.address, parseEther('0.8'));
      await middleman.connect(alice).notifyReward(bob.address, parseEther('0.8'));

      expect(await manager.nonces(middleman.address)).to.be.equal(2);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('1.5'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('998.5'));
      const reward = await manager.distributionList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.7'));
      expect(reward.propToken0).to.be.equal(4000);
      expect(reward.propToken1).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.isOutOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(await latestTime()));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      const rewardId = solidityKeccak256(['address', 'uint256'], [middleman.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);

      const reward2 = await manager.distributionList(1);
      expect(reward2.uniV3Pool).to.be.equal(pool.address);
      expect(reward2.rewardToken).to.be.equal(angle.address);
      expect(reward2.amount).to.be.equal(parseEther('0.8'));
      expect(reward2.propToken0).to.be.equal(3000);
      expect(reward2.propToken1).to.be.equal(2000);
      expect(reward2.propFees).to.be.equal(5000);
      expect(reward2.isOutOfRangeIncentivized).to.be.equal(0);
      expect(reward2.epochStart).to.be.equal(await pool.round(await latestTime()));
      expect(reward2.numEpoch).to.be.equal(10);
      expect(reward2.boostedReward).to.be.equal(0);
      expect(reward2.boostingAddress).to.be.equal(ZERO_ADDRESS);
      const rewardId2 = solidityKeccak256(['address', 'uint256'], [middleman.address, 1]);
      expect(reward2.rewardId).to.be.equal(rewardId2);
    });
  });
});
