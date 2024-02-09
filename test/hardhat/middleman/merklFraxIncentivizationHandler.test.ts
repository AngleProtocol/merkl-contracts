import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { parseEther, solidityKeccak256 } from 'ethers/lib/utils';
import { contract, ethers, web3 } from 'hardhat';

import {
  DistributionCreator,
  DistributionCreator__factory,
  MockCoreBorrow,
  MockCoreBorrow__factory,
  MockMerklFraxIncentivizationHandler,
  MockMerklFraxIncentivizationHandler__factory,
  MockToken,
  MockToken__factory,
  MockUniswapV3Pool,
  MockUniswapV3Pool__factory,
} from '../../../typechain';
import { parseAmount } from '../../../utils/bignumber';
import { inReceipt } from '../utils/expectEvent';
import { deployUpgradeableUUPS, latestTime, MAX_UINT256, ZERO_ADDRESS } from '../utils/helpers';

contract('MerklFraxIncentivizerHandler', () => {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let governor: SignerWithAddress;
  let guardian: SignerWithAddress;
  let angle: MockToken;
  let pool: MockUniswapV3Pool;
  let agEUR: string;

  let manager: DistributionCreator;
  let middleman: MockMerklFraxIncentivizationHandler;
  let core: MockCoreBorrow;
  let startTime: number;
  // eslint-disable-next-line
  let params: any;

  beforeEach(async () => {
    [deployer, alice, bob, governor, guardian] = await ethers.getSigners();
    angle = (await new MockToken__factory(deployer).deploy('ANGLE', 'ANGLE', 18)) as MockToken;
    core = (await new MockCoreBorrow__factory(deployer).deploy()) as MockCoreBorrow;
    pool = (await new MockUniswapV3Pool__factory(deployer).deploy()) as MockUniswapV3Pool;
    middleman = (await new MockMerklFraxIncentivizationHandler__factory(deployer).deploy(
      deployer.address,
    )) as MockMerklFraxIncentivizationHandler;
    await core.toggleGuardian(guardian.address);
    await core.toggleGovernor(governor.address);
    manager = (await deployUpgradeableUUPS(new DistributionCreator__factory(deployer))) as DistributionCreator;
    await manager.initialize(core.address, bob.address, parseAmount.gwei('0.1'));
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
    await manager.connect(governor).toggleTokenWhitelist(agEUR);
    await manager.connect(governor).toggleSigningWhitelist(middleman.address);
    await manager.connect(governor).setRewardTokenMinAmounts([angle.address], [1]);
    await middleman.setAddresses(manager.address);
  });
  describe('initializer', () => {
    it('success - values initialized', async () => {
      expect(await middleman.operatorAddress()).to.be.equal(deployer.address);
      expect(await middleman.merklDistributionCreator()).to.be.equal(manager.address);
    });
  });
  describe('setOperator', () => {
    it('reverts - access control', async () => {
      await expect(middleman.connect(alice).setOperator(alice.address)).to.be.revertedWith('Not owner or operator');
      await expect(middleman.connect(bob).setOperator(alice.address)).to.be.revertedWith('Not owner or operator');
      expect(await middleman.operatorAddress()).to.be.equal(deployer.address);
      expect(await middleman.owner()).to.be.equal(deployer.address);
      await middleman.connect(deployer).transferOwnership(bob.address);
      await middleman.connect(bob).setOperator(alice.address);
      expect(await middleman.operatorAddress()).to.be.equal(alice.address);
      await middleman.connect(alice).setOperator(guardian.address);
      expect(await middleman.operatorAddress()).to.be.equal(guardian.address);
      await expect(middleman.connect(alice).setOperator(alice.address)).to.be.revertedWith('Not owner or operator');
    });
  });
  describe('setGauge', () => {
    it('reverts - access control', async () => {
      await expect(middleman.connect(alice).setGauge(ZERO_ADDRESS, angle.address, params)).to.be.revertedWith(
        'Not owner or operator',
      );
      await middleman.connect(deployer).setOperator(alice.address);
      expect(await middleman.operatorAddress()).to.be.equal(alice.address);
      await middleman.connect(deployer).transferOwnership(bob.address);
      expect(await middleman.owner()).to.be.equal(bob.address);
      await expect(middleman.connect(deployer).setGauge(ZERO_ADDRESS, angle.address, params)).to.be.revertedWith(
        'Not owner or operator',
      );

      const receipt = await (await middleman.connect(bob).setGauge(alice.address, angle.address, params)).wait();
      inReceipt(receipt, 'GaugeSet', {
        gauge: alice.address,
      });
      const receipt2 = await (await middleman.connect(bob).setGauge(bob.address, angle.address, params)).wait();
      inReceipt(receipt2, 'GaugeSet', {
        gauge: bob.address,
      });
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
      await expect(
        middleman.connect(deployer).setGauge(ZERO_ADDRESS, angle.address, params),
      ).to.be.revertedWithCustomError(middleman, 'InvalidParams');
      await expect(
        middleman.connect(deployer).setGauge(alice.address, ZERO_ADDRESS, params),
      ).to.be.revertedWithCustomError(middleman, 'InvalidParams');
      // Pool does not have valid tokens 0 and 1
      await expect(middleman.connect(alice).setGauge(alice.address, angle.address, params)).to.be.reverted;
      await expect(middleman.connect(governor).setGauge(bob.address, angle.address, params1)).to.be.reverted;
    });
    it('success - value updated - token 0', async () => {
      await pool.setToken(agEUR, 0);
      const receipt = await (await middleman.connect(deployer).setGauge(alice.address, angle.address, params)).wait();
      inReceipt(receipt, 'GaugeSet', {
        gauge: alice.address,
      });
      const reward = await middleman.gaugeParams(alice.address, angle.address);
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
      const receipt = await (await middleman.connect(deployer).setGauge(alice.address, angle.address, params)).wait();
      inReceipt(receipt, 'GaugeSet', {
        gauge: alice.address,
      });
      const reward = await middleman.gaugeParams(alice.address, angle.address);
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
  describe('incentivizePool', () => {
    it('reverts - invalid params', async () => {
      await pool.setToken(agEUR, 1);
      await middleman.connect(deployer).setGauge(alice.address, angle.address, params);
      // No incentive token specified
      await expect(
        middleman
          .connect(bob)
          .incentivizePool(ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, 0, parseEther('0.5')),
      ).to.be.reverted;
      // No approval
      await expect(
        middleman
          .connect(bob)
          .incentivizePool(ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('0.5')),
      ).to.be.reverted;
      await expect(
        middleman
          .connect(alice)
          .incentivizePool(ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('0.5')),
      ).to.be.revertedWithCustomError(middleman, 'InvalidParams');
    });
    it('success - rewards well sent', async () => {
      await pool.setToken(agEUR, 1);
      await middleman.connect(deployer).setGauge(alice.address, angle.address, params);
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('0.7'));
      const time = await latestTime();
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.07'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.63'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('999.3'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(middleman.address);
      expect(reward.amount).to.be.equal(parseEther('0.63'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(time);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), middleman.address, angle.address, 2, time, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
      expect(await angle.allowance(middleman.address, manager.address)).to.be.equal(0);
    });
    it('success - rewards well sent - when gauge not whitelisted but tx origin is', async () => {
      await pool.setToken(agEUR, 1);
      await middleman.connect(deployer).setGauge(alice.address, angle.address, params);
      await manager.connect(governor).toggleSigningWhitelist(middleman.address);
      expect(await manager.userSignatureWhitelist(middleman.address)).to.be.equal(0);
      await manager.connect(governor).setMessage('hello');

      await expect(
        middleman
          .connect(alice)
          .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('0.7')),
      ).to.be.revertedWithCustomError(manager, 'NotSigned');

      await manager.connect(governor).toggleSigningWhitelist(alice.address);
      expect(await manager.userSignatureWhitelist(alice.address)).to.be.equal(1);
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('0.7'));
      const time = await latestTime();
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.07'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.63'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('999.3'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(middleman.address);
      expect(reward.amount).to.be.equal(parseEther('0.63'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(time);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), middleman.address, angle.address, 2, time, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
    });
    it('success - rewards well sent when zero amount', async () => {
      await pool.setToken(agEUR, 1);
      await middleman.connect(deployer).setGauge(alice.address, angle.address, params);
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('0'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('1000'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0'));
    });
    it('success - rewards kept when inferior to min distribution amount and then re-used', async () => {
      await pool.setToken(agEUR, 1);
      await middleman.connect(deployer).setGauge(alice.address, angle.address, params);
      await manager.connect(governor).setRewardTokenMinAmounts([angle.address], [parseEther('10')]);
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('5'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('5'));
      expect(await middleman.leftovers(angle.address, alice.address)).to.be.equal(parseEther('5'));
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('2'));
      expect(await middleman.leftovers(angle.address, alice.address)).to.be.equal(parseEther('7'));
      expect(await angle.balanceOf(middleman.address)).to.be.equal(parseEther('7'));
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('4'));
      expect(await middleman.leftovers(angle.address, alice.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('989'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(middleman.address);
      expect(reward.amount).to.be.equal(parseEther('9.9'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(await latestTime());
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [
          await deployer.getChainId(),
          middleman.address,
          angle.address,
          2,
          await latestTime(),
          1 * 60 * 60,
          campaignData,
        ],
      );
      expect(reward.campaignId).to.be.equal(campaignId);

      const params2 = {
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
        numEpoch: 2,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      await middleman.connect(deployer).setGauge(alice.address, angle.address, params2);
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('11'));
      expect(await middleman.leftovers(angle.address, alice.address)).to.be.equal(parseEther('11'));
      await middleman
        .connect(alice)
        .incentivizePool(alice.address, ZERO_ADDRESS, ZERO_ADDRESS, angle.address, 0, parseEther('12'));
      expect(await middleman.leftovers(angle.address, alice.address)).to.be.equal(parseEther('0'));
      const reward2 = await manager.campaignList(1);
      expect(reward2.campaignType).to.be.equal(2);
      expect(reward2.creator).to.be.equal(middleman.address);
      expect(reward2.amount).to.be.equal(parseEther('20.7'));
      expect(reward2.rewardToken).to.be.equal(angle.address);
      expect(reward2.startTimestamp).to.be.equal(await latestTime());
      expect(reward2.duration).to.be.equal(2 * 60 * 60);
      const campaignData2 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward2.campaignData).to.be.equal(campaignData2);
      const campaignId2 = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [
          await deployer.getChainId(),
          middleman.address,
          angle.address,
          2,
          await latestTime(),
          2 * 60 * 60,
          campaignData2,
        ],
      );
      expect(reward2.campaignId).to.be.equal(campaignId2);
    });
  });
});
