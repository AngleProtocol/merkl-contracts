import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';

import { MockAgEUR as ERC20 } from '../../typechain';

describe('Mock agEUR tests', async function () {
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let token: ERC20;

  before(async () => {
    [alice, bob] = await ethers.getSigners();
  });

  beforeEach(async () => {
    const MockAgEURFactory = await ethers.getContractFactory('MockAgEUR', { signer: alice });
    token = (await MockAgEURFactory.deploy()) as ERC20;
  });

  describe('Basic testing', async function () {
    it('success - check contract deployment', async () => {
      expect(await token.symbol()).to.equal('MTK');
      expect(await token.name()).to.equal('Mock Token');
      expect(await token.owner()).to.equal(alice.address);
    });
    it('success - mint', async () => {
      await expect(token.connect(alice).mint(bob.address, BigNumber.from(1))).to.emit(token, 'Transfer');
      expect(await token.balanceOf(bob.address)).to.equal(1);
      expect(await token.balanceOf(alice.address)).to.equal(0);
    });
  });
});
