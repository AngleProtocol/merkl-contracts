/*
// TODO: write tests back in Foundry
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { parseEther, solidityKeccak256 } from 'ethers/lib/utils';
import hre, { contract, ethers, web3,network } from 'hardhat';
import { Signer } from 'ethers';

import {
  DistributionCreator,
  DistributionCreator__factory,
  MockCoreBorrow,
  MockCoreBorrow__factory,
  MockToken,
  MockToken__factory,
  MockUniswapV3Pool,
  MockUniswapV3Pool__factory,
  PufferPointTokenWrapper,
  PufferPointTokenWrapper__factory
} from '../../../typechain';
import { parseAmount } from '../../../utils/bignumber';
import { inReceipt } from '../utils/expectEvent';
import { deployUpgradeableUUPS, increaseTime, latestTime, MAX_UINT256, ZERO_ADDRESS } from '../utils/helpers';

contract('PufferPointTokenWrapper', () => {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let governor: string;
  let guardian: string;
  let distributor: string;
  let distributionCreator: string;
  let feeRecipient: string;
  let angle: MockToken;
  let agEUR: MockToken;
  let tokenWrapper: PufferPointTokenWrapper;
  let cliffDuration: number;

  let manager: DistributionCreator;
  let core: MockCoreBorrow;

  const impersonatedSigners: { [key: string]: Signer } = {};

  beforeEach(async () => {
    [deployer, alice, bob] = await ethers.getSigners();
    await network.provider.request({
        method: 'hardhat_reset',
        params: [
          {
            forking: {
              jsonRpcUrl: process.env.ETH_NODE_URI_MAINNET,
              blockNumber: 21313975,
            },
          },
        ],
      });
        // add any addresses you want to impersonate here
        governor = '0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8';
        guardian = '0x0C2553e4B9dFA9f83b1A6D3EAB96c4bAaB42d430';
        distributor = '0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae';
        distributionCreator = '0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd';
        feeRecipient = '0xeaC6A75e19beB1283352d24c0311De865a867DAB'
        const impersonatedAddresses = [governor, guardian, distributor, distributionCreator, feeRecipient];

        for (const address of impersonatedAddresses) {
          await hre.network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [address],
          });
          await hre.network.provider.send('hardhat_setBalance', [address, '0x10000000000000000000000000000']);
          impersonatedSigners[address] = await ethers.getSigner(address);
        }

    angle = (await new MockToken__factory(deployer).deploy('ANGLE', 'ANGLE', 18)) as MockToken;
    core = (await new MockCoreBorrow__factory(deployer).deploy()) as MockCoreBorrow;
    await core.toggleGuardian(guardian);
    await core.toggleGovernor(governor);
    cliffDuration = 2592000;

    tokenWrapper = (await deployUpgradeableUUPS(new PufferPointTokenWrapper__factory(deployer))) as PufferPointTokenWrapper;
    await tokenWrapper.initialize(angle.address, cliffDuration, core.address, distributionCreator);
    await angle.mint(alice.address, parseEther('1000'));
  });
  describe('upgrade', () => {
    it('success - upgrades to new implementation', async () => {
      const newImplementation = await new PufferPointTokenWrapper__factory(deployer).deploy();
      await tokenWrapper.connect(impersonatedSigners[governor]).upgradeTo(newImplementation.address);
    });
    it('reverts - when called by unallowed address', async () => {
        const newImplementation = await new PufferPointTokenWrapper__factory(deployer).deploy();
      await expect(tokenWrapper.connect(alice).upgradeTo(newImplementation.address)).to.be.revertedWithCustomError(
        tokenWrapper,
        'NotGovernor',
      );
    });
  });
  describe('initializer', () => {
    it('success - treasury', async () => {
      expect(await tokenWrapper.cliffDuration()).to.be.equal(cliffDuration);
      expect(await tokenWrapper.core()).to.be.equal(core.address);
      expect(await tokenWrapper.underlying()).to.be.equal(angle.address);
    });
    it('reverts - already initialized', async () => {
      await expect(tokenWrapper.initialize(angle.address, cliffDuration,core.address, distributionCreator)).to.be.revertedWith(
        'Initializable: contract is already initialized',
      );
    });
    it('reverts - zero address', async () => {
       const tokenWrapperRevert = (await deployUpgradeableUUPS(new PufferPointTokenWrapper__factory(deployer))) as PufferPointTokenWrapper;
      await expect(
        tokenWrapperRevert.initialize(ZERO_ADDRESS,cliffDuration, core.address, distributionCreator),
      ).to.be.reverted;
    });
  });
  describe('createCampaign', () => {
    it('success - balance credited', async () => {
        await angle.connect(alice).approve(tokenWrapper.address, MAX_UINT256);
        await tokenWrapper.connect(alice).transfer(distributor,parseEther('1'));
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('1'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('1'));
      });
      it('success - balance credited - feeRecipient', async () => {
        await angle.connect(alice).approve(tokenWrapper.address, MAX_UINT256);
        await tokenWrapper.connect(alice).transfer(feeRecipient,parseEther('1'));
        expect(await tokenWrapper.balanceOf(feeRecipient)).to.be.equal(0);
        expect(await angle.balanceOf(feeRecipient)).to.be.equal(parseEther('1'));
      });
      it('reverts - when other contract', async () => {
        await angle.connect(alice).approve(tokenWrapper.address, MAX_UINT256);
        await expect(tokenWrapper.connect(alice).transfer(governor,parseEther('1'))).to.be.reverted;
      });
  });
  describe('claimRewards', () => {
    it('success - balance credited', async () => {
        await angle.connect(alice).approve(tokenWrapper.address, MAX_UINT256);
        await tokenWrapper.connect(alice).transfer(distributor,parseEther('1'));
        await tokenWrapper.connect(impersonatedSigners[distributor]).transfer(bob.address, parseEther('0.5'));
        const endData = await latestTime();
        expect(await tokenWrapper.balanceOf(bob.address)).to.be.equal(0);
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.5'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('1'));

        const vestings = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings[0][0].amount).to.be.equal(parseEther('0.5'));
        expect(vestings[0][0].unlockTimestamp).to.be.equal(endData+cliffDuration);
        expect(vestings[1]).to.be.equal(0);

        await increaseTime(cliffDuration/2);
        expect(await tokenWrapper.claimable(bob.address)).to.be.equal(0);
        await increaseTime(cliffDuration*2);
        expect(await tokenWrapper.claimable(bob.address)).to.be.equal(parseEther('0.5'));
        await tokenWrapper.claim(bob.address);
        expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.5'))
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.5'));

        const vestings2 = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings2[0][0].amount).to.be.equal(parseEther('0.5'));
        expect(vestings2[0][0].unlockTimestamp).to.be.equal(endData+cliffDuration);
        expect(vestings2[1]).to.be.equal(1);

        await tokenWrapper.connect(impersonatedSigners[distributor]).transfer(bob.address, parseEther('0.2'));
        const endTime2 = await latestTime();
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.3'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.5'));
        const vestings3 = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings3[0][1].amount).to.be.equal(parseEther('0.2'));
        expect(vestings3[0][1].unlockTimestamp).to.be.equal(endTime2+cliffDuration);
        expect(vestings3[1]).to.be.equal(1);

        await increaseTime(cliffDuration/2);
        expect(await tokenWrapper.claimable(bob.address)).to.be.equal(0);
        await tokenWrapper.connect(impersonatedSigners[distributor]).transfer(bob.address, parseEther('0.12'));
        const endTime3 = await latestTime();
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.18'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.5'));

        const vestings4 = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings4[0][1].amount).to.be.equal(parseEther('0.2'));
        expect(vestings4[0][1].unlockTimestamp).to.be.equal(endTime2+cliffDuration);
        expect(vestings4[1]).to.be.equal(1);
        expect(vestings4[0][2].amount).to.be.equal(parseEther('0.12'));
        expect(vestings4[0][2].unlockTimestamp).to.be.equal(endTime3+cliffDuration);

        await increaseTime(cliffDuration*3/4);
        expect(await tokenWrapper.claimable(bob.address)).to.be.equal(parseEther('0.2'));

        await tokenWrapper.claim(bob.address)
        expect(await tokenWrapper.claimable(bob.address)).to.be.equal(parseEther('0'));
        expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.7'))
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.3'));

        const vestings5 = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings5[0][1].amount).to.be.equal(parseEther('0.2'));
        expect(vestings5[0][1].unlockTimestamp).to.be.equal(endTime2+cliffDuration);
        expect(vestings5[1]).to.be.equal(2);

        await tokenWrapper.connect(impersonatedSigners[distributor]).transfer(bob.address, parseEther('0.1'));
        const endTime4 = await latestTime();
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.08'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.3'));
        const vestings6 = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings6[0][3].amount).to.be.equal(parseEther('0.1'));
        expect(vestings6[0][3].unlockTimestamp).to.be.equal(endTime4+cliffDuration);
        expect(vestings6[1]).to.be.equal(2);

        await tokenWrapper.connect(impersonatedSigners[distributor]).transfer(alice.address, parseEther('0.05'));
        const endTime5 = await latestTime();
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.03'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.3'));
        const vestings7 = await tokenWrapper.getUserVestings(alice.address);
        expect(vestings7[0][0].amount).to.be.equal(parseEther('0.05'));
        expect(vestings7[0][0].unlockTimestamp).to.be.equal(endTime5+cliffDuration);
        expect(vestings7[1]).to.be.equal(0);

        await increaseTime(cliffDuration*2);
        expect(await tokenWrapper.claimable(bob.address)).to.be.equal(parseEther('0.22'));
        expect(await tokenWrapper.claimable(alice.address)).to.be.equal(parseEther('0.05'));
        await tokenWrapper.claim(bob.address);
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.03'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.08'));
        expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.92'));

        const vestings8 = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings8[1]).to.be.equal(4);
        expect(await tokenWrapper.claimable(bob.address)).to.be.equal(0);

        await tokenWrapper.claim(alice.address);
        const vestings9 = await tokenWrapper.getUserVestings(alice.address);
        expect(vestings9[1]).to.be.equal(1);
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.03'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.03'));
        expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.92'));
        expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('999.05'));

        await tokenWrapper.claim(alice.address);
        await tokenWrapper.claim(bob.address);
        const vestings10 = await tokenWrapper.getUserVestings(alice.address);
        const vestings11 = await tokenWrapper.getUserVestings(bob.address);
        expect(vestings10[1]).to.be.equal(1);
        expect(vestings11[1]).to.be.equal(4);
        expect(await tokenWrapper.balanceOf(distributor)).to.be.equal(parseEther('0.03'));
        expect(await angle.balanceOf(tokenWrapper.address)).to.be.equal(parseEther('0.03'));
        expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.92'));
        expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('999.05'));
      });
  });
});
*/