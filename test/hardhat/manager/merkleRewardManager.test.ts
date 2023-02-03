import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { parseEther, solidityKeccak256 } from 'ethers/lib/utils';
import { contract, ethers, web3 } from 'hardhat';

import {
  MerkleRewardManager,
  MerkleRewardManager__factory,
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

contract('MerkleRewardManager', () => {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let governor: SignerWithAddress;
  let guardian: SignerWithAddress;
  let angle: MockToken;
  let pool: MockUniswapV3Pool;
  let agEUR: string;

  let manager: MerkleRewardManager;
  let coreBorrow: MockCoreBorrow;
  let startTime: number;
  // eslint-disable-next-line
  let params: any;

  beforeEach(async () => {
    [deployer, alice, bob, governor, guardian] = await ethers.getSigners();
    angle = (await new MockToken__factory(deployer).deploy('ANGLE', 'ANGLE', 18)) as MockToken;
    coreBorrow = (await new MockCoreBorrow__factory(deployer).deploy()) as MockCoreBorrow;
    pool = (await new MockUniswapV3Pool__factory(deployer).deploy()) as MockUniswapV3Pool;
    await coreBorrow.toggleGuardian(guardian.address);
    await coreBorrow.toggleGovernor(governor.address);
    manager = (await deployUpgradeableUUPS(new MerkleRewardManager__factory(deployer))) as MerkleRewardManager;
    await manager.initialize(coreBorrow.address, bob.address, parseAmount.gwei('0.1'));
    startTime = await latestTime();
    params = {
      uniV3Pool: pool.address,
      token: angle.address,
      positionWrappers: [alice.address, bob.address, deployer.address],
      wrapperTypes: [0, 1, 2],
      amount: parseEther('1'),
      propToken1: 4000,
      propToken2: 2000,
      propFees: 4000,
      outOfRangeIncentivized: 0,
      epochStart: startTime,
      numEpoch: 1,
      boostedReward: 0,
      boostingAddress: ZERO_ADDRESS,
      rewardId: web3.utils.soliditySha3('TEST') as string,
      additionalData: web3.utils.soliditySha3('test2ng') as string,
    };
    agEUR = '0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8';
    await angle.mint(alice.address, parseEther('1000'));
    await angle.connect(alice).approve(manager.address, MAX_UINT256);
    await manager.connect(guardian).toggleTokenWhitelist(agEUR);
    await manager.connect(guardian).toggleSigningWhitelist(alice.address);
  });

  describe('initializer', () => {
    it('success - treasury', async () => {
      expect(await manager.merkleRootDistributor()).to.be.equal(bob.address);
      expect(await manager.coreBorrow()).to.be.equal(coreBorrow.address);
      expect(await manager.fees()).to.be.equal(parseAmount.gwei('0.1'));
      expect(await manager.isWhitelistedToken(agEUR)).to.be.equal(1);
    });
    it('reverts - already initialized', async () => {
      await expect(manager.initialize(coreBorrow.address, bob.address, parseAmount.gwei('0.1'))).to.be.revertedWith(
        'Initializable: contract is already initialized',
      );
    });
    it('reverts - zero address', async () => {
      const managerRevert = (await deployUpgradeableUUPS(
        new MerkleRewardManager__factory(deployer),
      )) as MerkleRewardManager;
      await expect(
        managerRevert.initialize(ZERO_ADDRESS, bob.address, parseAmount.gwei('0.1')),
      ).to.be.revertedWithCustomError(managerRevert, 'ZeroAddress');
      await expect(
        managerRevert.initialize(coreBorrow.address, ZERO_ADDRESS, parseAmount.gwei('0.1')),
      ).to.be.revertedWithCustomError(managerRevert, 'ZeroAddress');
      await expect(
        managerRevert.initialize(coreBorrow.address, bob.address, parseAmount.gwei('1.1')),
      ).to.be.revertedWithCustomError(managerRevert, 'InvalidParam');
    });
  });
  describe('upgrade', () => {
    it('success - upgrades to new implementation', async () => {
      const newImplementation = await new MerkleRewardManager__factory(deployer).deploy();
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
      const newImplementation2 = await new MerkleRewardManager__factory(deployer).deploy();
      await manager.connect(guardian).upgradeTo(newImplementation2.address);
      /*
      console.log(
        await ethers.provider.getStorageAt(
          manager.address,
          '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
        ),
        newImplementation2.address,
      );
      */
    });
    it('reverts - when called by unallowed address', async () => {
      const newImplementation = await new MerkleRewardManager__factory(deployer).deploy();
      await expect(manager.connect(alice).upgradeTo(newImplementation.address)).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
    });
  });
  describe('Access Control', () => {
    it('reverts - not governor or guardian', async () => {
      await expect(manager.connect(alice).setNewMerkleRootDistributor(ZERO_ADDRESS)).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
      await expect(manager.connect(alice).setFees(parseAmount.gwei('0.1'))).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
      await expect(
        manager.connect(alice).setUserFeeRebate(ZERO_ADDRESS, parseAmount.gwei('0.1')),
      ).to.be.revertedWithCustomError(manager, 'NotGovernorOrGuardian');
      await expect(manager.connect(alice).recoverFees([], ZERO_ADDRESS)).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
      await expect(manager.connect(alice).setMessage('hello')).to.be.revertedWithCustomError(
        manager,
        'NotGovernorOrGuardian',
      );
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
        'NotGovernorOrGuardian',
      );
    });
  });
  describe('setNewMerkleRootDistributor', () => {
    it('reverts - zero address', async () => {
      await expect(manager.connect(guardian).setNewMerkleRootDistributor(ZERO_ADDRESS)).to.be.revertedWithCustomError(
        manager,
        'InvalidParam',
      );
    });
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(guardian).setNewMerkleRootDistributor(alice.address)).wait();
      inReceipt(receipt, 'MerkleRootDistributorUpdated', {
        _merkleRootDistributor: alice.address,
      });
      expect(await manager.merkleRootDistributor()).to.be.equal(alice.address);
    });
  });
  describe('setFees', () => {
    it('reverts - zero address', async () => {
      await expect(manager.connect(guardian).setFees(parseAmount.gwei('1.1'))).to.be.revertedWithCustomError(
        manager,
        'InvalidParam',
      );
    });
    it('success - value updated', async () => {
      const receipt = await (await manager.connect(guardian).setFees(parseAmount.gwei('0.13'))).wait();
      inReceipt(receipt, 'FeesSet', {
        _fees: parseAmount.gwei('0.13'),
      });
      expect(await manager.fees()).to.be.equal(parseAmount.gwei('0.13'));
    });
  });
  describe('setFeeRecipient', () => {
    it('success - value updated', async () => {
      expect(await manager.feeRecipient()).to.be.equal(ZERO_ADDRESS);
      const receipt = await (await manager.connect(guardian).setFeeRecipient(deployer.address)).wait();
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
      const receipt2 = await (await manager.connect(guardian).toggleTokenWhitelist(agEUR)).wait();
      inReceipt(receipt2, 'TokenWhitelistToggled', {
        token: agEUR,
        toggleStatus: 0,
      });
      expect(await manager.isWhitelistedToken(agEUR)).to.be.equal(0);
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
      const receipt = await (await manager.connect(guardian).setMessage('hello')).wait();
      const msgHash = await manager.messageHash();
      expect(await manager.message()).to.be.equal('hello');

      inReceipt(receipt, 'MessageUpdated', {
        _messageHash: msgHash,
      });

      const receipt2 = await (await manager.connect(guardian).setMessage('hello2')).wait();
      const msgHash2 = await manager.messageHash();
      expect(await manager.message()).to.be.equal('hello2');

      inReceipt(receipt2, 'MessageUpdated', {
        _messageHash: msgHash2,
      });
    });
  });

  describe('recoverFees', () => {
    it('success - fees recovered', async () => {
      await manager.connect(guardian).recoverFees([], deployer.address);
      await angle.mint(manager.address, parseAmount.gwei('100'));
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('100'));
      await manager.connect(guardian).recoverFees([angle.address], deployer.address);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('0'));
      expect(await angle.balanceOf(deployer.address)).to.be.equal(parseAmount.gwei('100'));
      const usdc = (await new MockToken__factory(deployer).deploy('usdc', 'usdc', 18)) as MockToken;
      await angle.mint(manager.address, parseAmount.gwei('100'));
      await usdc.mint(manager.address, parseAmount.gwei('33'));
      await manager.connect(guardian).recoverFees([angle.address, usdc.address], deployer.address);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('0'));
      // 100 + 100
      expect(await angle.balanceOf(deployer.address)).to.be.equal(parseAmount.gwei('200'));
      expect(await usdc.balanceOf(manager.address)).to.be.equal(parseAmount.gwei('0'));
      expect(await usdc.balanceOf(deployer.address)).to.be.equal(parseAmount.gwei('33'));
    });
  });
  describe('sign', () => {
    it('success - correct signature', async () => {
      await manager.connect(guardian).setMessage('hello');
      const signature = await alice.signMessage('hello');
      const receipt = await (await manager.connect(alice).sign(signature)).wait();
      const messageHash = await manager.messageHash();
      expect(await manager.userSignatures(alice.address)).to.be.equal(messageHash);
      inReceipt(receipt, 'UserSigned', {
        messageHash: messageHash,
        user: alice.address,
      });
    });
    it('reverts - invalid signature', async () => {
      await manager.connect(guardian).setMessage('hello');
      const signature = await alice.signMessage('hello2');
      await expect(manager.connect(alice).sign(signature)).to.be.revertedWithCustomError(manager, 'InvalidSignature');
    });
  });
  describe('signAndDepositReward', () => {
    it('success - correct signature', async () => {
      await manager.connect(guardian).toggleSigningWhitelist(alice.address);
      await manager.connect(guardian).setMessage('hello');
      const signature = await alice.signMessage('hello');
      const receipt = await (await manager.connect(alice).signAndDepositReward(params, signature)).wait();
      const messageHash = await manager.messageHash();
      expect(await manager.userSignatures(alice.address)).to.be.equal(messageHash);
      inReceipt(receipt, 'UserSigned', {
        messageHash: messageHash,
        user: alice.address,
      });
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      const rewardId = solidityKeccak256(['address', 'uint256'], [alice.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);
    });
    it('reverts - invalid signature', async () => {
      await manager.connect(guardian).toggleSigningWhitelist(alice.address);
      await manager.connect(guardian).setMessage('hello');
      const signature = await alice.signMessage('hello2');
      await expect(manager.connect(alice).signAndDepositReward(params, signature)).to.be.revertedWithCustomError(
        manager,
        'InvalidSignature',
      );
    });
  });
  describe('depositReward', () => {
    it('reverts - invalid reward', async () => {
      const param0 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: 0,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param1 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 0,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param2 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: 0,
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param3 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2001,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param4 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 3999,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const param5 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 1,
        boostedReward: 9999,
        boostingAddress: bob.address,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const params6 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 10,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      await expect(manager.connect(alice).depositReward(param0)).to.be.revertedWithCustomError(
        manager,
        'InvalidReward',
      );
      await expect(manager.connect(alice).depositReward(param1)).to.be.revertedWithCustomError(
        manager,
        'InvalidReward',
      );
      await expect(manager.connect(alice).depositReward(param2)).to.be.revertedWithCustomError(
        manager,
        'InvalidReward',
      );
      await expect(manager.connect(alice).depositReward(param3)).to.be.revertedWithCustomError(
        manager,
        'InvalidReward',
      );
      await expect(manager.connect(alice).depositReward(param4)).to.be.revertedWithCustomError(
        manager,
        'InvalidReward',
      );
      await expect(manager.connect(alice).depositReward(param5)).to.be.revertedWithCustomError(
        manager,
        'InvalidReward',
      );
      await expect(manager.connect(alice).depositReward(params6)).to.be.revertedWithCustomError(
        manager,
        'InvalidReward',
      );
    });
    it('reverts - has not signed', async () => {
      await manager.connect(guardian).setMessage('hello');
      await expect(manager.connect(deployer).depositReward(params)).to.be.revertedWithCustomError(manager, 'NotSigned');
      await expect(manager.connect(deployer).depositRewards([params])).to.be.revertedWithCustomError(
        manager,
        'NotSigned',
      );
    });
    it('reverts - has signed but an old message', async () => {
      await manager.connect(guardian).setMessage('hello');
      const signature = await deployer.signMessage('hello');
      const receipt = await (await manager.connect(deployer).sign(signature)).wait();
      const messageHash = await manager.messageHash();
      expect(await manager.userSignatures(deployer.address)).to.be.equal(messageHash);
      inReceipt(receipt, 'UserSigned', {
        messageHash: messageHash,
        user: deployer.address,
      });
      await manager.connect(guardian).setMessage('hello2');
      await expect(manager.connect(deployer).depositReward(params)).to.be.revertedWithCustomError(manager, 'NotSigned');
      await expect(manager.connect(deployer).depositRewards([params])).to.be.revertedWithCustomError(
        manager,
        'NotSigned',
      );
    });
    it('success - has not signed but no message to sign', async () => {
      await manager.connect(guardian).toggleSigningWhitelist(alice.address);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      expect(reward.additionalData).to.be.equal(web3.utils.soliditySha3('test2ng'));
      const rewardId = solidityKeccak256(['address', 'uint256'], [alice.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);
    });
    it('success - when no fee rebate or agEUR pool', async () => {
      expect(await manager.nonces(alice.address)).to.be.equal(0);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      const rewardId = solidityKeccak256(['address', 'uint256'], [alice.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);
    });
    it('success - when no fee rebate or agEUR pool and a fee recipient', async () => {
      expect(await manager.nonces(alice.address)).to.be.equal(0);
      await manager.connect(guardian).setFeeRecipient(deployer.address);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(deployer.address)).to.be.equal(parseEther('0.1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.9'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.9'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      const rewardId = solidityKeccak256(['address', 'uint256'], [alice.address, 0]);
      expect(reward.rewardId).to.be.equal(rewardId);
    });
    it('success - when a fee rebate for the specific address 1/2', async () => {
      // 50% rebate on fee
      await manager.connect(guardian).setUserFeeRebate(alice.address, parseAmount.gwei('0.5'));
      expect(await manager.nonces(alice.address)).to.be.equal(0);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0.05'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.95'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('0.95'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
    });
    it('success - when a fee rebate for the specific address 2/2', async () => {
      // 50% rebate on fee
      await manager.connect(guardian).setUserFeeRebate(alice.address, parseAmount.gwei('1.1'));
      expect(await manager.nonces(alice.address)).to.be.equal(0);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('1'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('1'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
    });
    it('success - when agEUR is a token 1/2', async () => {
      // 50% rebate on fee
      await pool.setToken(agEUR, 0);
      expect(await manager.nonces(alice.address)).to.be.equal(0);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('1'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('1'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
    });
    it('success - when agEUR is a token 2/2', async () => {
      // 50% rebate on fee
      await pool.setToken(agEUR, 1);
      expect(await manager.nonces(alice.address)).to.be.equal(0);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('1'));
      const reward = await manager.rewardList(0);
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('1'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
    });
    it('success - view functions check', async () => {
      // 50% rebate on fee
      await pool.setToken(agEUR, 0);
      expect(await manager.nonces(alice.address)).to.be.equal(0);
      await manager.connect(alice).depositReward(params);
      expect(await manager.nonces(alice.address)).to.be.equal(1);
      const allRewards = await manager.getAllRewards();
      expect(allRewards.length).to.be.equal(1);
      const reward = allRewards[0];
      expect(reward.uniV3Pool).to.be.equal(pool.address);
      expect(reward.token).to.be.equal(angle.address);
      expect(reward.amount).to.be.equal(parseEther('1'));
      expect(reward.propToken1).to.be.equal(4000);
      expect(reward.propToken2).to.be.equal(2000);
      expect(reward.propFees).to.be.equal(4000);
      expect(reward.outOfRangeIncentivized).to.be.equal(0);
      expect(reward.epochStart).to.be.equal(await pool.round(startTime));
      expect(reward.numEpoch).to.be.equal(1);
      expect(reward.boostedReward).to.be.equal(0);
      expect(reward.boostingAddress).to.be.equal(ZERO_ADDRESS);
      expect(allRewards[0].positionWrappers[0]).to.be.equal(alice.address);
      expect(allRewards[0].positionWrappers[1]).to.be.equal(bob.address);
      expect(allRewards[0].positionWrappers[2]).to.be.equal(deployer.address);
      expect(allRewards[0].wrapperTypes[0]).to.be.equal(0);
      expect(allRewards[0].wrapperTypes[1]).to.be.equal(1);
      expect(allRewards[0].wrapperTypes[2]).to.be.equal(2);

      const activeRewards = await manager.getActiveRewards();
      expect(activeRewards.length).to.be.equal(1);
      expect(activeRewards[0].positionWrappers[0]).to.be.equal(alice.address);
      expect(activeRewards[0].positionWrappers[1]).to.be.equal(bob.address);
      expect(activeRewards[0].positionWrappers[2]).to.be.equal(deployer.address);

      expect(activeRewards[0].wrapperTypes[0]).to.be.equal(0);
      expect(activeRewards[0].wrapperTypes[1]).to.be.equal(1);
      expect(activeRewards[0].wrapperTypes[2]).to.be.equal(2);

      const rewardsForEpoch = await manager.getRewardsForEpoch(startTime);
      expect(rewardsForEpoch.length).to.be.equal(1);
      expect(rewardsForEpoch[0].positionWrappers[0]).to.be.equal(alice.address);
      expect(rewardsForEpoch[0].positionWrappers[1]).to.be.equal(bob.address);
      expect(rewardsForEpoch[0].positionWrappers[2]).to.be.equal(deployer.address);
      expect(rewardsForEpoch[0].wrapperTypes[0]).to.be.equal(0);
      expect(rewardsForEpoch[0].wrapperTypes[1]).to.be.equal(1);
      expect(rewardsForEpoch[0].wrapperTypes[2]).to.be.equal(2);
      expect((await manager.getRewardsForEpoch(startTime + 3600)).length).to.be.equal(0);

      const poolRewards = await manager.getActivePoolRewards(pool.address);
      expect(poolRewards.length).to.be.equal(1);
      expect(poolRewards[0].positionWrappers[0]).to.be.equal(alice.address);
      expect(poolRewards[0].positionWrappers[1]).to.be.equal(bob.address);
      expect(poolRewards[0].positionWrappers[2]).to.be.equal(deployer.address);
      expect(poolRewards[0].wrapperTypes[0]).to.be.equal(0);
      expect(poolRewards[0].wrapperTypes[1]).to.be.equal(1);
      expect(poolRewards[0].wrapperTypes[2]).to.be.equal(2);
      expect((await manager.getActivePoolRewards(bob.address)).length).to.be.equal(0);

      const poolRewardsForEpoch = await manager.getPoolRewardsForEpoch(pool.address, startTime);
      expect(poolRewardsForEpoch.length).to.be.equal(1);
      expect(poolRewardsForEpoch[0].positionWrappers[0]).to.be.equal(alice.address);
      expect(poolRewardsForEpoch[0].positionWrappers[1]).to.be.equal(bob.address);
      expect(poolRewardsForEpoch[0].positionWrappers[2]).to.be.equal(deployer.address);
      expect(poolRewardsForEpoch[0].wrapperTypes[0]).to.be.equal(0);
      expect(poolRewardsForEpoch[0].wrapperTypes[1]).to.be.equal(1);
      expect(poolRewardsForEpoch[0].wrapperTypes[2]).to.be.equal(2);
      expect((await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600)).length).to.be.equal(0);
    });
    it('success - when spans over several epochs', async () => {
      await pool.setToken(agEUR, 0);
      const params2 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 10,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('toong') as string,
      };
      await manager.connect(alice).depositReward(params2);
      const poolRewardsForEpoch = await manager.getPoolRewardsForEpoch(pool.address, startTime);
      expect(poolRewardsForEpoch.length).to.be.equal(1);
      expect(poolRewardsForEpoch[0].positionWrappers[0]).to.be.equal(alice.address);
      expect(poolRewardsForEpoch[0].positionWrappers[1]).to.be.equal(bob.address);
      expect(poolRewardsForEpoch[0].positionWrappers[2]).to.be.equal(deployer.address);
      expect((await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600 * 9)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600 * 10)).length).to.be.equal(0);
      const rewardsForEpoch = await manager.getRewardsForEpoch(startTime);
      expect(rewardsForEpoch.length).to.be.equal(1);
      expect(rewardsForEpoch[0].positionWrappers[0]).to.be.equal(alice.address);
      expect(rewardsForEpoch[0].positionWrappers[1]).to.be.equal(bob.address);
      expect(rewardsForEpoch[0].positionWrappers[2]).to.be.equal(deployer.address);
      expect((await manager.getRewardsForEpoch(startTime + 3600)).length).to.be.equal(1);
      expect((await manager.getRewardsForEpoch(startTime + 3600 * 9)).length).to.be.equal(1);
      expect((await manager.getRewardsForEpoch(startTime + 3600 * 10)).length).to.be.equal(0);

      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 9, startTime + 3600 * 10)).length).to.be.equal(
        1,
      );
      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 10, startTime + 3600 * 13)).length).to.be.equal(
        0,
      );
      expect((await manager.getRewardsBetweenEpochs(startTime - 1, startTime)).length).to.be.equal(0);
      expect((await manager.getRewardsBetweenEpochs(startTime - 1, startTime + 3600)).length).to.be.equal(1);
      expect((await manager.getRewardsBetweenEpochs(startTime - 1, startTime + 3600 * 11)).length).to.be.equal(1);
      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 4, startTime + 3600 * 9)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsBetweenEpochs(pool.address, startTime - 1, startTime)).length).to.be.equal(0);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(pool.address, startTime - 1, startTime + 3600)).length,
      ).to.be.equal(1);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(pool.address, startTime - 1, startTime + 3600 * 11)).length,
      ).to.be.equal(1);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(pool.address, startTime + 3600 * 4, startTime + 3600 * 9)).length,
      ).to.be.equal(1);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(alice.address, startTime - 1, startTime + 3600)).length,
      ).to.be.equal(0);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(alice.address, startTime - 1, startTime + 3600 * 11)).length,
      ).to.be.equal(0);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(alice.address, startTime + 3600 * 4, startTime + 3600 * 9)).length,
      ).to.be.equal(0);
      expect((await manager.getRewardsAfterEpoch(startTime)).length).to.be.equal(1);
      expect((await manager.getRewardsAfterEpoch(0)).length).to.be.equal(1);
      expect((await manager.getRewardsAfterEpoch(startTime + 3600 * 9)).length).to.be.equal(1);
      expect((await manager.getRewardsAfterEpoch(startTime + 3600 * 10)).length).to.be.equal(0);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, startTime)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, 0)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, startTime + 3600 * 9)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, startTime + 3600 * 10)).length).to.be.equal(0);
      expect((await manager.getPoolRewardsAfterEpoch(alice.address, startTime)).length).to.be.equal(0);
      expect((await manager.getPoolRewardsAfterEpoch(alice.address, 0)).length).to.be.equal(0);
      expect((await manager.getPoolRewardsAfterEpoch(alice.address, startTime + 3600 * 9)).length).to.be.equal(0);
    });
  });
  describe('depositRewards', () => {
    it('success - when multiple rewards over multiple periods and multiple pools', async () => {
      const mockPool = (await new MockUniswapV3Pool__factory(deployer).deploy()) as MockUniswapV3Pool;
      const params0 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('1'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime,
        numEpoch: 3,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test0ng') as string,
      };
      const params1 = {
        uniV3Pool: mockPool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('2'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime + 3600,
        numEpoch: 1,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test1ng') as string,
      };
      const params2 = {
        uniV3Pool: pool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('3'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime + 3600 * 2,
        numEpoch: 3,

        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test2ng') as string,
      };
      const params3 = {
        uniV3Pool: mockPool.address,
        token: angle.address,
        positionWrappers: [alice.address, bob.address, deployer.address],
        wrapperTypes: [0, 0, 0],
        amount: parseEther('4'),
        propToken1: 4000,
        propToken2: 2000,
        propFees: 4000,
        outOfRangeIncentivized: 0,
        epochStart: startTime + 3600 * 10,
        numEpoch: 3,
        boostedReward: 0,
        boostingAddress: ZERO_ADDRESS,
        rewardId: web3.utils.soliditySha3('TEST') as string,
        additionalData: web3.utils.soliditySha3('test3ng') as string,
      };
      await manager.connect(alice).depositRewards([params0, params1, params2, params3]);
      // 10% of 1+2+3+4
      expect(await angle.balanceOf(manager.address)).to.be.equal(parseEther('1'));
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('9'));
      expect((await manager.rewardList(0)).amount).to.be.equal(parseEther('0.9'));
      expect((await manager.rewardList(1)).amount).to.be.equal(parseEther('1.8'));
      expect((await manager.rewardList(2)).amount).to.be.equal(parseEther('2.7'));
      expect((await manager.rewardList(3)).amount).to.be.equal(parseEther('3.6'));
      expect((await manager.rewardList(0)).additionalData).to.be.equal(web3.utils.soliditySha3('test0ng'));
      expect((await manager.rewardList(1)).additionalData).to.be.equal(web3.utils.soliditySha3('test1ng'));
      expect((await manager.rewardList(2)).additionalData).to.be.equal(web3.utils.soliditySha3('test2ng'));
      expect((await manager.rewardList(3)).additionalData).to.be.equal(web3.utils.soliditySha3('test3ng'));
      expect((await manager.rewardList(0)).rewardId).to.be.equal(
        solidityKeccak256(['address', 'uint256'], [alice.address, 0]),
      );
      expect((await manager.rewardList(1)).rewardId).to.be.equal(
        solidityKeccak256(['address', 'uint256'], [alice.address, 1]),
      );
      expect((await manager.rewardList(2)).rewardId).to.be.equal(
        solidityKeccak256(['address', 'uint256'], [alice.address, 2]),
      );
      expect((await manager.rewardList(3)).rewardId).to.be.equal(
        solidityKeccak256(['address', 'uint256'], [alice.address, 3]),
      );
      expect(await manager.nonces(alice.address)).to.be.equal(4);

      expect((await manager.getAllRewards()).length).to.be.equal(4);

      const activeRewards = await manager.getActiveRewards();
      expect(activeRewards.length).to.be.equal(1);
      expect(activeRewards[0].amount).to.be.equal(parseEther('0.9'));

      const activePoolRewards = await manager.getActivePoolRewards(pool.address);
      expect(activePoolRewards.length).to.be.equal(1);
      expect(activePoolRewards[0].amount).to.be.equal(parseEther('0.9'));
      expect(await manager.getActivePoolRewards(mockPool.address));

      const epochRewards0 = await manager.getRewardsForEpoch(startTime + 3600);
      expect(epochRewards0.length).to.be.equal(2);
      expect(epochRewards0[0].amount).to.be.equal(parseEther('0.9'));
      expect(epochRewards0[1].amount).to.be.equal(parseEther('1.8'));

      const epochRewards1 = await manager.getRewardsForEpoch(startTime + 3600 * 2);
      expect(epochRewards1.length).to.be.equal(2);
      expect(epochRewards1[0].amount).to.be.equal(parseEther('0.9'));
      expect(epochRewards1[1].amount).to.be.equal(parseEther('2.7'));

      const epochRewards2 = await manager.getRewardsForEpoch(startTime + 3600 * 3);
      expect(epochRewards2.length).to.be.equal(1);
      expect(epochRewards2[0].amount).to.be.equal(parseEther('2.7'));

      const epochRewards3 = await manager.getRewardsForEpoch(startTime + 3600 * 10);
      expect(epochRewards3.length).to.be.equal(1);
      expect(epochRewards3[0].amount).to.be.equal(parseEther('3.6'));

      const poolRewards0 = await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600);
      expect(poolRewards0.length).to.be.equal(1);
      expect(poolRewards0[0].amount).to.be.equal(parseEther('0.9'));

      const poolRewards1 = await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600 * 2);
      expect(poolRewards1.length).to.be.equal(2);
      expect(poolRewards1[0].amount).to.be.equal(parseEther('0.9'));
      expect(poolRewards1[1].amount).to.be.equal(parseEther('2.7'));

      const poolRewards2 = await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600 * 3);
      expect(poolRewards2.length).to.be.equal(1);
      expect(poolRewards2[0].amount).to.be.equal(parseEther('2.7'));

      const poolRewards3 = await manager.getPoolRewardsForEpoch(pool.address, startTime + 3600 * 10);
      expect(poolRewards3.length).to.be.equal(0);

      const poolRewards01 = await manager.getPoolRewardsForEpoch(mockPool.address, startTime + 3600);
      expect(poolRewards01.length).to.be.equal(1);
      expect(poolRewards01[0].amount).to.be.equal(parseEther('1.8'));

      const poolRewards11 = await manager.getPoolRewardsForEpoch(mockPool.address, startTime + 3600 * 2);
      expect(poolRewards11.length).to.be.equal(0);

      const poolRewards21 = await manager.getPoolRewardsForEpoch(mockPool.address, startTime + 3600 * 3);
      expect(poolRewards21.length).to.be.equal(0);

      const poolRewards31 = await manager.getPoolRewardsForEpoch(mockPool.address, startTime + 3600 * 10);
      expect(poolRewards31.length).to.be.equal(1);
      expect(poolRewards31[0].amount).to.be.equal(parseEther('3.6'));

      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 9, startTime + 3600 * 10)).length).to.be.equal(
        0,
      );
      expect((await manager.getRewardsBetweenEpochs(startTime, startTime + 3600 * 2)).length).to.be.equal(2);
      expect((await manager.getRewardsBetweenEpochs(startTime, startTime + 3600 * 3)).length).to.be.equal(3);
      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 2, startTime + 3600 * 3)).length).to.be.equal(2);
      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 4, startTime + 3600 * 11)).length).to.be.equal(
        2,
      );
      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 4, startTime + 3600 * 10)).length).to.be.equal(
        1,
      );
      expect((await manager.getRewardsBetweenEpochs(startTime + 3600 * 10, startTime + 3600 * 12)).length).to.be.equal(
        1,
      );
      expect((await manager.getRewardsAfterEpoch(startTime)).length).to.be.equal(4);
      expect((await manager.getRewardsAfterEpoch(startTime + 3600 * 2)).length).to.be.equal(3);
      expect((await manager.getRewardsAfterEpoch(startTime + 3600 * 3)).length).to.be.equal(2);
      expect((await manager.getRewardsAfterEpoch(startTime + 3600 * 5)).length).to.be.equal(1);
      expect((await manager.getRewardsAfterEpoch(startTime + 3600 * 13)).length).to.be.equal(0);
      expect((await manager.getPoolRewardsBetweenEpochs(pool.address, startTime, startTime + 3600)).length).to.be.equal(
        1,
      );
      expect(
        (await manager.getPoolRewardsBetweenEpochs(pool.address, startTime, startTime + 2 * 3600)).length,
      ).to.be.equal(1);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(mockPool.address, startTime, startTime + 2 * 3600)).length,
      ).to.be.equal(1);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(mockPool.address, startTime + 3 * 3600, startTime + 10 * 3600))
          .length,
      ).to.be.equal(0);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(pool.address, startTime, startTime + 3 * 3600)).length,
      ).to.be.equal(2);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(pool.address, startTime + 3 * 3600, startTime + 100 * 3600)).length,
      ).to.be.equal(1);
      expect(
        (await manager.getPoolRewardsBetweenEpochs(mockPool.address, startTime + 3 * 3600, startTime + 100 * 3600))
          .length,
      ).to.be.equal(1);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, startTime)).length).to.be.equal(2);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, startTime + 3600 * 2)).length).to.be.equal(2);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, startTime + 3600 * 3)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsAfterEpoch(pool.address, startTime + 3600 * 5)).length).to.be.equal(0);
      expect((await manager.getPoolRewardsAfterEpoch(mockPool.address, startTime + 3600 * 1)).length).to.be.equal(2);
      expect((await manager.getPoolRewardsAfterEpoch(mockPool.address, startTime + 3600 * 2)).length).to.be.equal(1);
      expect((await manager.getPoolRewardsAfterEpoch(mockPool.address, startTime + 3600 * 13)).length).to.be.equal(0);
    });
  });
});
