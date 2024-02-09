import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { parseEther, solidityKeccak256 } from 'ethers/lib/utils';
import { contract, ethers, web3 } from 'hardhat';

import {
  DistributionCreator,
  DistributionCreator__factory,
  MockCoreBorrow,
  MockCoreBorrow__factory,
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
  let agEUR: MockToken;
  let token0: MockToken;
  let token1: MockToken;

  let manager: DistributionCreator;
  let core: MockCoreBorrow;
  let startTime: number;
  // eslint-disable-next-line
  let params: any;
  let campaignsParams: any;

  beforeEach(async () => {
    [deployer, alice, bob, governor, guardian] = await ethers.getSigners();
    angle = (await new MockToken__factory(deployer).deploy('ANGLE', 'ANGLE', 18)) as MockToken;
    token0 = (await new MockToken__factory(deployer).deploy('token0', 'token0', 18)) as MockToken;
    token1 = (await new MockToken__factory(deployer).deploy('token1', 'token1', 18)) as MockToken;
    agEUR = (await new MockToken__factory(deployer).deploy('agEUR', 'agEUR', 18)) as MockToken;
    core = (await new MockCoreBorrow__factory(deployer).deploy()) as MockCoreBorrow;
    pool = (await new MockUniswapV3Pool__factory(deployer).deploy()) as MockUniswapV3Pool;
    await pool.setToken(token0.address, 0);
    await pool.setToken(token1.address, 1);
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
      epochStart: startTime + 1000,
      numEpoch: 1,
      boostedReward: 0,
      boostingAddress: ZERO_ADDRESS,
      rewardId: web3.utils.soliditySha3('TEST') as string,
      additionalData: web3.utils.soliditySha3('test2ng') as string,
    };
    campaignsParams = {
      campaignId: web3.utils.soliditySha3('TEST') as string,
      creator: alice.address,
      rewardToken: angle.address,
      startTimestamp: startTime + 1000,
      campaignType: 2,
      duration: 1 * 60 * 60,
      amount: parseEther('0.9'),
      campaignData: ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      ),
    };
    await angle.mint(alice.address, parseEther('1000'));
    await angle.connect(alice).approve(manager.address, MAX_UINT256);
    await manager.connect(guardian).toggleTokenWhitelist(agEUR.address);
    await manager.connect(guardian).toggleSigningWhitelist(alice.address);
    await manager.connect(guardian).setRewardTokenMinAmounts([angle.address], [1]);
  });

  describe('upgrade', () => {
    it('success - upgrades to new implementation', async () => {
      const newImplementation = await new DistributionCreator__factory(deployer).deploy();
      await manager.connect(governor).upgradeTo(newImplementation.address);
      /*
      console.log(
        await ethers.provider.getStorageAt(
          manager.address,
          '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
        ),
        newImplementation.address,
      );
      */
    });

    it('reverts - when called by unallowed address', async () => {
      const newImplementation = await new DistributionCreator__factory(deployer).deploy();
      await expect(manager.connect(alice).upgradeTo(newImplementation.address)).to.be.revertedWithCustomError(
        manager,
        'NotGovernor',
      );
    });
  });

  describe('initializer', () => {
    it('success - treasury', async () => {
      expect(await manager.distributor()).to.be.equal(bob.address);
      expect(await manager.core()).to.be.equal(core.address);
      expect(await manager.defaultFees()).to.be.equal(parseAmount.gwei('0.1'));
      expect(await manager.isWhitelistedToken(agEUR.address)).to.be.equal(1);
      expect(await manager.rewardTokens(0)).to.be.equal(angle.address);
      expect(await manager.rewardTokenMinAmounts(angle.address)).to.be.equal(1);
    });
    it('reverts - already initialized', async () => {
      await expect(manager.initialize(core.address, bob.address, parseAmount.gwei('0.1'))).to.be.revertedWith(
        'Initializable: contract is already initialized',
      );
    });
    it('reverts - zero address', async () => {
      const managerRevert = (await deployUpgradeableUUPS(
        new DistributionCreator__factory(deployer),
      )) as DistributionCreator;
      await expect(
        managerRevert.initialize(ZERO_ADDRESS, bob.address, parseAmount.gwei('0.1')),
      ).to.be.revertedWithCustomError(managerRevert, 'ZeroAddress');
      await expect(
        managerRevert.initialize(core.address, ZERO_ADDRESS, parseAmount.gwei('0.1')),
      ).to.be.revertedWithCustomError(managerRevert, 'ZeroAddress');
      await expect(
        managerRevert.initialize(core.address, bob.address, parseAmount.gwei('1.1')),
      ).to.be.revertedWithCustomError(managerRevert, 'InvalidParam');
    });
  });
  describe('Access Control', () => {
    it('reverts - not governor or guardian', async () => {
      await expect(manager.connect(alice).setNewDistributor(ZERO_ADDRESS)).to.be.revertedWithCustomError(
        manager,
        'NotGovernor',
      );
      await expect(manager.connect(alice).setFees(parseAmount.gwei('0.1'))).to.be.revertedWithCustomError(
        manager,
        'NotGovernor',
      );
      await expect(manager.connect(alice).setCampaignFees('2', parseAmount.gwei('0.1'))).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
      await expect(
        manager.connect(alice).setUserFeeRebate(ZERO_ADDRESS, parseAmount.gwei('0.1')),
      ).to.be.revertedWithCustomError(manager, 'NotGovernorOrGuardian');
      await expect(manager.connect(alice).recoverFees([], ZERO_ADDRESS)).to.be.revertedWithCustomError(
        manager,
        'NotGovernor',
      );
      await expect(manager.connect(alice).setMessage('hello')).to.be.revertedWithCustomError(manager, 'NotGovernor');
      await expect(manager.connect(alice).toggleSigningWhitelist(deployer.address)).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
      await expect(manager.connect(alice).toggleTokenWhitelist(deployer.address)).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
      await expect(manager.connect(alice).setFeeRecipient(deployer.address)).to.be.revertedWithCustomError(
        manager,
        'NotGovernor',
      );
      await expect(manager.connect(alice).setRewardTokenMinAmounts([angle.address], [1])).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
    });
  });
  describe('setNewDistributor', () => {
    it('reverts - zero address', async () => {
      await expect(manager.connect(governor).setNewDistributor(ZERO_ADDRESS)).to.be.revertedWithCustomError(
        manager,
        'InvalidParam',
      );
    });
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(governor).setNewDistributor(alice.address)).wait();
      inReceipt(receipt, 'DistributorUpdated', {
        _distributor: alice.address,
      });
      expect(await manager.distributor()).to.be.equal(alice.address);
    });
  });
  describe('setCampaignFees', () => {
    it('reverts - wrong fees', async () => {
      await expect(
        manager.connect(guardian).setCampaignFees('2', parseAmount.gwei('1.1')),
      ).to.be.revertedWithCustomError(manager, 'InvalidParam');
    });
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(guardian).setCampaignFees('2', '100000000')).wait();
      inReceipt(receipt, 'CampaignSpecificFeesSet', {
        campaignType: '2',
        _fees: '100000000',
      });
      expect(await manager.campaignSpecificFees('2')).to.be.equal('100000000');
    });
  });
  describe('setFees', () => {
    it('reverts - wrong fees', async () => {
      await expect(manager.connect(governor).setFees(parseAmount.gwei('1.1'))).to.be.revertedWithCustomError(
        manager,
        'InvalidParam',
      );
    });
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(governor).setFees('100000000')).wait();
      inReceipt(receipt, 'FeesSet', {
        _fees: '100000000',
      });
      expect(await manager.defaultFees()).to.be.equal('100000000');
    });
  });
  describe('setFeeRecipient', () => {
    it('success - value updated', async () => {
      expect(await manager.feeRecipient()).to.be.equal(ZERO_ADDRESS);
      const receipt = await (await manager.connect(governor).setFeeRecipient(deployer.address)).wait();
      inReceipt(receipt, 'FeeRecipientUpdated', {
        _feeRecipient: deployer.address,
      });
      expect(await manager.feeRecipient()).to.be.equal(deployer.address);
    });
  });
  describe('setUserFeeRebate', () => {
    it('success - value updated', async () => {
      const receipt = await (
        await manager.connect(guardian).setUserFeeRebate(deployer.address, parseAmount.gwei('0.13'))
      ).wait();
      inReceipt(receipt, 'FeeRebateUpdated', {
        user: deployer.address,
        userFeeRebate: parseAmount.gwei('0.13'),
      });
      expect(await manager.feeRebate(deployer.address)).to.be.equal(parseAmount.gwei('0.13'));
    });
  });
  describe('toggleTokenWhitelist', () => {
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(guardian).toggleTokenWhitelist(deployer.address)).wait();
      inReceipt(receipt, 'TokenWhitelistToggled', {
        token: deployer.address,
        toggleStatus: 1,
      });
      expect(await manager.isWhitelistedToken(deployer.address)).to.be.equal(1);
      const receipt2 = await (await manager.connect(guardian).toggleTokenWhitelist(agEUR.address)).wait();
      inReceipt(receipt2, 'TokenWhitelistToggled', {
        token: agEUR.address,
        toggleStatus: 0,
      });
      expect(await manager.isWhitelistedToken(agEUR.address)).to.be.equal(0);
    });
  });
  describe('toggleSigningWhitelist', () => {
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(guardian).toggleSigningWhitelist(deployer.address)).wait();
      inReceipt(receipt, 'UserSigningWhitelistToggled', {
        user: deployer.address,
        toggleStatus: 1,
      });
      expect(await manager.userSignatureWhitelist(deployer.address)).to.be.equal(1);
      const receipt2 = await (await manager.connect(guardian).toggleSigningWhitelist(alice.address)).wait();
      inReceipt(receipt2, 'UserSigningWhitelistToggled', {
        user: alice.address,
        toggleStatus: 0,
      });
      expect(await manager.userSignatureWhitelist(alice.address)).to.be.equal(0);
    });
  });
  describe('setMessage', () => {
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(governor).setMessage('hello')).wait();
      const msgHash = await manager.messageHash();
      expect(await manager.message()).to.be.equal('hello');

      inReceipt(receipt, 'MessageUpdated', {
        _messageHash: msgHash,
      });

      const receipt2 = await (await manager.connect(governor).setMessage('hello2')).wait();
      const msgHash2 = await manager.messageHash();
      expect(await manager.message()).to.be.equal('hello2');

      inReceipt(receipt2, 'MessageUpdated', {
        _messageHash: msgHash2,
      });
    });
  });
  describe('setRewardTokenMinAmounts', () => {
    it('success - value updated for a set of tokens', async () => {
      const receipt = await (
        await manager
          .connect(guardian)
          .setRewardTokenMinAmounts([agEUR.address, angle.address], [parseEther('1'), parseEther('2')])
      ).wait();
      inReceipt(receipt, 'RewardTokenMinimumAmountUpdated', {
        token: agEUR.address,
        amount: parseEther('1'),
      });
      inReceipt(receipt, 'RewardTokenMinimumAmountUpdated', {
        token: angle.address,
        amount: parseEther('2'),
      });
      expect(await manager.rewardTokenMinAmounts(agEUR.address)).to.be.equal(parseEther('1'));
      expect(await manager.rewardTokenMinAmounts(angle.address)).to.be.equal(parseEther('2'));
      expect(await manager.rewardTokens(0)).to.be.equal(angle.address);
      expect(await manager.rewardTokens(1)).to.be.equal(agEUR.address);

      const rewardTokenList = await manager['getValidRewardTokens()']();
      expect(rewardTokenList.length).to.be.equal(2);
      expect(rewardTokenList[0].token).to.be.equal(angle.address);
      expect(rewardTokenList[0].minimumAmountPerEpoch).to.be.equal(parseEther('2'));
      expect(rewardTokenList[1].token).to.be.equal(agEUR.address);
      expect(rewardTokenList[1].minimumAmountPerEpoch).to.be.equal(parseEther('1'));

      await manager
        .connect(guardian)
        .setRewardTokenMinAmounts([agEUR.address, angle.address], [parseEther('4'), parseEther('0')]);
      expect(await manager.rewardTokenMinAmounts(agEUR.address)).to.be.equal(parseEther('4'));
      expect(await manager.rewardTokenMinAmounts(angle.address)).to.be.equal(parseEther('0'));
      expect(await manager.rewardTokens(0)).to.be.equal(angle.address);
      expect(await manager.rewardTokens(1)).to.be.equal(agEUR.address);

      const rewardTokenList2 = await manager['getValidRewardTokens()']();
      expect(rewardTokenList2.length).to.be.equal(1);
      expect(rewardTokenList2[0].token).to.be.equal(agEUR.address);
      expect(rewardTokenList2[0].minimumAmountPerEpoch).to.be.equal(parseEther('4'));

      await manager
        .connect(guardian)
        .setRewardTokenMinAmounts([agEUR.address, angle.address], [parseEther('7'), parseEther('5')]);
      expect(await manager.rewardTokens(0)).to.be.equal(angle.address);
      expect(await manager.rewardTokens(1)).to.be.equal(agEUR.address);
      expect(await manager.rewardTokens(2)).to.be.equal(angle.address);

      const rewardTokenList3 = await manager['getValidRewardTokens()']();
      expect(rewardTokenList3.length).to.be.equal(3);
      expect(rewardTokenList3[0].token).to.be.equal(angle.address);
      expect(rewardTokenList3[0].minimumAmountPerEpoch).to.be.equal(parseEther('5'));
      expect(rewardTokenList3[1].token).to.be.equal(agEUR.address);
      expect(rewardTokenList3[1].minimumAmountPerEpoch).to.be.equal(parseEther('7'));
      expect(rewardTokenList3[2].token).to.be.equal(angle.address);
      expect(rewardTokenList3[2].minimumAmountPerEpoch).to.be.equal(parseEther('5'));

      await expect(
        manager.connect(guardian).setRewardTokenMinAmounts([agEUR.address], [parseEther('7'), parseEther('5')]),
      ).to.be.revertedWithCustomError(manager, 'InvalidLengths');
    });
  });

  describe('recoverFees', () => {
    it('success - fees recovered', async () => {
      await manager.connect(governor).recoverFees([], deployer.address);
      await angle.mint(manager.address, parseAmount.gwei('100'));
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('100'));
      await manager.connect(governor).recoverFees([angle.address], deployer.address);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('0'));
      expect(await angle.balanceOf(deployer.address)).to.be.equal(parseAmount.gwei('100'));
      const usdc = (await new MockToken__factory(deployer).deploy('usdc', 'usdc', 18)) as MockToken;
      await angle.mint(manager.address, parseAmount.gwei('100'));
      await usdc.mint(manager.address, parseAmount.gwei('33'));
      await manager.connect(governor).recoverFees([angle.address, usdc.address], deployer.address);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('0'));
      // 100 + 100
      expect(await angle.balanceOf(deployer.address)).to.be.equal(parseAmount.gwei('200'));
      expect(await usdc.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('0'));
      expect(await usdc.balanceOf(deployer.address)).to.be.equal(parseAmount.gwei('33'));
    });
  });
  describe('sign', () => {
    it('success - correct signature', async () => {
      await manager.connect(governor).setMessage('hello');
      const signature = await alice.signMessage('hello');
      const receipt = await (await manager.connect(alice).sign(signature)).wait();
      const messageHash = await manager.messageHash();
      expect(await manager.userSignatures(alice.address)).to.be.equal(messageHash);
      inReceipt(receipt, 'UserSigned', {
        messageHash,
        user: alice.address,
      });
    });
    it('reverts - invalid signature', async () => {
      await manager.connect(governor).setMessage('hello');
      const signature = await alice.signMessage('hello2');
      await expect(manager.connect(alice).sign(signature)).to.be.revertedWithCustomError(manager, 'InvalidSignature');
    });
  });
  describe('signAndCreateCampaign', () => {
    it('success - correct signature', async () => {
      await manager.connect(governor).toggleSigningWhitelist(alice.address);
      await manager.connect(governor).setMessage('hello');
      const signature = await alice.signMessage('hello');
      const receipt = await (await manager.connect(alice).signAndCreateCampaign(campaignsParams, signature)).wait();
      const messageHash = await manager.messageHash();

      expect(await manager.userSignatures(alice.address)).to.be.equal(messageHash);
      inReceipt(receipt, 'UserSigned', {
        messageHash,
        user: alice.address,
      });
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.09'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.81'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(alice.address);
      expect(reward.amount).to.be.equal(parseEther('0.81'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(startTime + 1000);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), alice.address, angle.address, 2, startTime + 1000, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
    });
    it('reverts - invalid signature', async () => {
      await manager.connect(governor).toggleSigningWhitelist(alice.address);
      await manager.connect(governor).setMessage('hello');
      const signature = await alice.signMessage('hello2');
      await expect(
        manager.connect(alice).signAndCreateCampaign(campaignsParams, signature),
      ).to.be.revertedWithCustomError(manager, 'InvalidSignature');
    });
  });
  describe('createDistribution', () => {
    it('reverts - invalid reward', async () => {
      const param0 = {
        uniV3Pool: pool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: 0,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param1 = {
        uniV3Pool: pool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 1000,
        numEpoch: 0,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param2 = {
        uniV3Pool: pool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: 0,
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 1000,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param3 = {
        uniV3Pool: pool.address,
        rewardToken: agEUR.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken0: 4000,
        propToken1: 2001,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 1000,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      await expect(manager.connect(alice).createDistribution(param0)).to.be.revertedWithCustomError(
        manager,
        'CampaignSouldStartInFuture',
      );
      await expect(manager.connect(alice).createDistribution(param1)).to.be.revertedWithCustomError(
        manager,
        'CampaignDurationBelowHour',
      );
      await expect(manager.connect(alice).createDistribution(param2)).to.be.revertedWithCustomError(
        manager,
        'CampaignRewardTooLow',
      );
      await expect(manager.connect(alice).createDistribution(param3)).to.be.revertedWithCustomError(
        manager,
        'CampaignRewardTokenNotWhitelisted',
      );

      await manager.connect(guardian).setRewardTokenMinAmounts([angle.address], [parseEther('100000')]);
      await expect(manager.connect(alice).createDistribution(params)).to.be.revertedWithCustomError(
        manager,
        'CampaignRewardTooLow',
      );
    });
    it('reverts - has not signed', async () => {
      await manager.connect(governor).setMessage('hello');
      await expect(manager.connect(deployer).createDistribution(params)).to.be.revertedWithCustomError(
        manager,
        'NotSigned',
      );
      await expect(manager.connect(deployer).createDistributions([params])).to.be.revertedWithCustomError(
        manager,
        'NotSigned',
      );
    });
    it('reverts - has signed but an old message', async () => {
      await manager.connect(governor).setMessage('hello');
      const signature = await deployer.signMessage('hello');
      const receipt = await (await manager.connect(deployer).sign(signature)).wait();
      const messageHash = await manager.messageHash();
      expect(await manager.userSignatures(deployer.address)).to.be.equal(messageHash);
      inReceipt(receipt, 'UserSigned', {
        messageHash,
        user: deployer.address,
      });
      await manager.connect(governor).setMessage('hello2');
      await expect(manager.connect(deployer).createDistribution(params)).to.be.revertedWithCustomError(
        manager,
        'NotSigned',
      );
      await expect(manager.connect(deployer).createDistributions([params])).to.be.revertedWithCustomError(
        manager,
        'NotSigned',
      );
    });
    it('success - has not signed but no message to sign', async () => {
      await manager.connect(guardian).toggleSigningWhitelist(alice.address);
      await manager.connect(alice).createDistribution(params);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(alice.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(startTime + 1000);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), alice.address, angle.address, 2, startTime + 1000, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
    });
    it('success - when no fee rebate or agEUR pool', async () => {
      await manager.connect(alice).createDistribution(params);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(alice.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(startTime + 1000);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), alice.address, angle.address, 2, startTime + 1000, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
    });
    it('success - when no fee rebate or agEUR pool and a fee recipient', async () => {
      await manager.connect(governor).setFeeRecipient(deployer.address);
      await manager.connect(alice).createDistribution(params);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(deployer.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(alice.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(startTime + 1000);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), alice.address, angle.address, 2, startTime + 1000, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
    });
    it('success - when a fee rebate for the specific address 1/2', async () => {
      // 50% rebate on fee
      await manager.connect(guardian).setUserFeeRebate(alice.address, parseAmount.gwei('0.5'));
      await manager.connect(alice).createDistribution(params);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.05'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.95'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(alice.address);
      expect(reward.amount).to.be.equal(parseEther('0.95'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(startTime + 1000);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), alice.address, angle.address, 2, startTime + 1000, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
    });
    it('success - when a fee rebate for the specific address 2/2', async () => {
      // 50% rebate on fee
      await manager.connect(guardian).setUserFeeRebate(alice.address, parseAmount.gwei('1'));
      await manager.connect(alice).createDistribution(params);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('1'));
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(alice.address);
      expect(reward.amount).to.be.equal(parseEther('1'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(startTime + 1000);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), alice.address, angle.address, 2, startTime + 1000, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);
    });
    it('success - view functions check', async () => {
      // 50% rebate on fee
      await pool.setToken(agEUR.address, 0);
      await manager.connect(alice).createDistribution(params);
      const reward = await manager.campaignList(0);
      expect(reward.campaignType).to.be.equal(2);
      expect(reward.creator).to.be.equal(alice.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.rewardToken).to.be.equal(angle.address);
      expect(reward.startTimestamp).to.be.equal(startTime + 1000);
      expect(reward.duration).to.be.equal(1 * 60 * 60);
      const campaignData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
        [pool.address, 4000, 4000, 2000, 0, ZERO_ADDRESS, 0, [alice.address], [], '0x'],
      );
      expect(reward.campaignData).to.be.equal(campaignData);
      const campaignId = solidityKeccak256(
        ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
        [await deployer.getChainId(), alice.address, angle.address, 2, startTime + 1000, 1 * 60 * 60, campaignData],
      );
      expect(reward.campaignId).to.be.equal(campaignId);

      const rewardsForEpoch = await manager.getCampaignsBetween(startTime + 1000, startTime + 1000 + 60 * 60, 0, 1);
      expect(rewardsForEpoch[0].length).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 1000 + 3600, startTime + 1000 + 3600 + 60 * 60, 0, 1))[0].length,
      ).to.be.equal(0);
    });
    it('success - when spans over several epochs', async () => {
      await pool.setToken(agEUR.address, 0);
      const params2 = {
        uniV3Pool: pool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 100,
        numEpoch: 10,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('toong') as string,
      };
      await manager.connect(alice).createDistribution(params2);
      const poolRewardsForEpoch = await manager.getCampaignsBetween(startTime + 100, startTime + 100 + 3600 * 10, 0, 1);
      expect(poolRewardsForEpoch[0].length).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600, startTime + 100 + 3600 * 2, 0, 1))[0].length,
      ).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 9, startTime + 100 + 3600 * 10, 0, 1))[0].length,
      ).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 10, startTime + 100 + 3600 * 11, 0, 1))[0].length,
      ).to.be.equal(0);

      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 9, startTime + 100 + 3600 * 10, 0, 1))[0].length,
      ).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 10, startTime + 100 + 3600 * 13, 0, 1))[0].length,
      ).to.be.equal(0);
      expect((await manager.getCampaignsBetween(startTime + 100 - 1, startTime + 100, 0, 1))[0].length).to.be.equal(0);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 - 1, startTime + 100 + 3600, 0, 1))[0].length,
      ).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 - 1, startTime + 100 + 3600 * 11, 0, 1))[0].length,
      ).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 4, startTime + 100 + 3600 * 9, 0, 1))[0].length,
      ).to.be.equal(1);
    });
  });
  describe('createDistributions', () => {
    it('success - when multiple rewards over multiple periods and multiple pools', async () => {
      const mockPool = (await new MockUniswapV3Pool__factory(deployer).deploy()) as MockUniswapV3Pool;
      await mockPool.setToken(token0.address, 0);
      await mockPool.setToken(token1.address, 1);
      const params0 = {
        uniV3Pool: pool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 100,
        numEpoch: 3,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test0ng') as string,
      };
      const params1 = {
        uniV3Pool: mockPool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('2'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 3700,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test1ng') as string,
      };
      const params2 = {
        uniV3Pool: pool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('3'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 3600 * 2 + 100,
        numEpoch: 3,

        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const params3 = {
        uniV3Pool: mockPool.address,
        rewardToken: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('4'),
        propToken0: 4000,
        propToken1: 2000,
        propFees: 4000,
        isOutOfRangeIncentivized: 0,
        epochStart: startTime + 3600 * 10 + 100,
        numEpoch: 3,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test3ng') as string,
      };
      await manager.connect(alice).createDistributions([params0, params1, params2, params3]);
      // 10% of 1+2+3+4
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('9'));
      expect((await manager.campaignList(0)).amount).to.be.equal(parseEther('0.9'));
      expect((await manager.campaignList(1)).amount).to.be.equal(parseEther('1.8'));
      expect((await manager.campaignList(2)).amount).to.be.equal(parseEther('2.7'));
      expect((await manager.campaignList(3)).amount).to.be.equal(parseEther('3.6'));

      expect((await manager.campaignList(0)).campaignId).to.be.equal(
        solidityKeccak256(
          ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
          [
            await deployer.getChainId(),
            alice.address,
            angle.address,
            2,
            startTime + 100,
            3 * 60 * 60,
            ethers.utils.defaultAbiCoder.encode(
              ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
              [
                pool.address,
                4000,
                4000,
                2000,
                0,
                ZERO_ADDRESS,
                0,
                [alice.address, bob.address, deployer.address],
                [],
                '0x',
              ],
            ),
          ],
        ),
      );
      expect((await manager.campaignList(1)).campaignId).to.be.equal(
        solidityKeccak256(
          ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
          [
            await deployer.getChainId(),
            alice.address,
            angle.address,
            2,
            startTime + 3700,
            1 * 60 * 60,
            ethers.utils.defaultAbiCoder.encode(
              ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
              [
                mockPool.address,
                4000,
                4000,
                2000,
                0,
                ZERO_ADDRESS,
                0,
                [alice.address, bob.address, deployer.address],
                [],
                '0x',
              ],
            ),
          ],
        ),
      );
      expect((await manager.campaignList(2)).campaignId).to.be.equal(
        solidityKeccak256(
          ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
          [
            await deployer.getChainId(),
            alice.address,
            angle.address,
            2,
            startTime + 3600 * 2 + 100,
            3 * 60 * 60,
            ethers.utils.defaultAbiCoder.encode(
              ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
              [
                pool.address,
                4000,
                4000,
                2000,
                0,
                ZERO_ADDRESS,
                0,
                [alice.address, bob.address, deployer.address],
                [],
                '0x',
              ],
            ),
          ],
        ),
      );
      expect((await manager.campaignList(3)).campaignId).to.be.equal(
        solidityKeccak256(
          ['uint256', 'address', 'address', 'uint32', 'uint32', 'uint32', 'bytes'],
          [
            await deployer.getChainId(),
            alice.address,
            angle.address,
            2,
            startTime + 3600 * 10 + 100,
            3 * 60 * 60,
            ethers.utils.defaultAbiCoder.encode(
              ['address', 'uint', 'uint', 'uint', 'uint', 'address', 'uint', 'address[]', 'address[]', 'string'],
              [
                mockPool.address,
                4000,
                4000,
                2000,
                0,
                ZERO_ADDRESS,
                0,
                [alice.address, bob.address, deployer.address],
                [],
                '0x',
              ],
            ),
          ],
        ),
      );

      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 9, startTime + 100 + 3600 * 10, 0, 10))[0].length,
      ).to.be.equal(0);
      expect(
        (await manager.getCampaignsBetween(startTime + 100, startTime + 100 + 3600 * 2, 0, 10))[0].length,
      ).to.be.equal(2);
      expect(
        (await manager.getCampaignsBetween(startTime + 100, startTime + 100 + 3600 * 3, 0, 10))[0].length,
      ).to.be.equal(3);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 2, startTime + 100 + 3600 * 3, 0, 10))[0].length,
      ).to.be.equal(2);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 4, startTime + 100 + 3600 * 11, 0, 10))[0].length,
      ).to.be.equal(2);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 4, startTime + 100 + 3600 * 10, 0, 10))[0].length,
      ).to.be.equal(1);
      expect(
        (await manager.getCampaignsBetween(startTime + 100 + 3600 * 10, startTime + 100 + 3600 * 12, 0, 10))[0].length,
      ).to.be.equal(1);
    });
  });
});
