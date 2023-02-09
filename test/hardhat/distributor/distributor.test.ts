import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, constants } from 'ethers';
import { keccak256, parseEther, parseUnits } from 'ethers/lib/utils';
import { contract, ethers, web3 } from 'hardhat';
import { MerkleTree } from 'merkletreejs';

import {
  Distributor,
  Distributor__factory,
  MockCoreBorrow,
  MockCoreBorrow__factory,
  MockToken,
  MockToken__factory,
} from '../../../typechain';
import { inReceipt } from '../utils/expectEvent';
import { deployUpgradeableUUPS, increaseTime, latestTime, MerkleTreeType, ZERO_ADDRESS } from '../utils/helpers';

contract('Distributor', () => {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let governor: SignerWithAddress;
  let guardian: SignerWithAddress;
  let angle: MockToken;

  let distributor: Distributor;
  let coreBorrow: MockCoreBorrow;
  let merkleTree: MerkleTreeType;
  const emptyBytes = '0x0000000000000000000000000000000000000000000000000000000000000000';

  beforeEach(async () => {
    [deployer, alice, bob, governor, guardian] = await ethers.getSigners();
    angle = (await new MockToken__factory(deployer).deploy('ANGLE', 'ANGLE', 18)) as MockToken;
    coreBorrow = (await new MockCoreBorrow__factory(deployer).deploy()) as MockCoreBorrow;
    await coreBorrow.toggleGuardian(guardian.address);
    await coreBorrow.toggleGovernor(governor.address);
    distributor = (await deployUpgradeableUUPS(new Distributor__factory(deployer))) as Distributor;
    await distributor.initialize(coreBorrow.address);
    merkleTree = { merkleRoot: web3.utils.keccak256('MERKLE_ROOT'), ipfsHash: web3.utils.keccak256('IPFS_HASH') };
  });
  describe('upgrade', () => {
    it('success - upgrades to new implementation', async () => {
      const newImplementation = await new Distributor__factory(deployer).deploy();
      await distributor.connect(governor).upgradeTo(newImplementation.address);
      /*
      console.log(
        await ethers.provider.getStorageAt(
          distributor.address,
          '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
        ),
        newImplementation.address,
      );
      */

      const newImplementation2 = await new Distributor__factory(deployer).deploy();
      await distributor.connect(guardian).upgradeTo(newImplementation2.address);
      /*
      console.log(
        await ethers.provider.getStorageAt(
          distributor.address,
          '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
        ),
        newImplementation2.address,
      );
      */
    });
    it('reverts - when called by unallowed address', async () => {
      const newImplementation = await new Distributor__factory(deployer).deploy();
      await expect(distributor.connect(alice).upgradeTo(newImplementation.address)).to.be.revertedWithCustomError(
        distributor,
        'NotGovernorOrGuardian',
      );
    });
  });

  describe('initializer', () => {
    it('success - coreBorrow', async () => {
      expect(await distributor.coreBorrow()).to.be.equal(coreBorrow.address);
    });
    it('reverts - already initialized', async () => {
      await expect(distributor.initialize(coreBorrow.address)).to.be.revertedWith(
        'Initializable: contract is already initialized',
      );
    });
    it('reverts - zero address', async () => {
      const distributorRevert = (await deployUpgradeableUUPS(new Distributor__factory(deployer))) as Distributor;
      await expect(distributorRevert.initialize(ZERO_ADDRESS)).to.be.reverted;
    });
  });
  describe('toggleTrusted', () => {
    it('reverts - not guardian', async () => {
      await expect(distributor.connect(alice).toggleTrusted(bob.address)).to.be.revertedWithCustomError(
        distributor,
        'NotGovernorOrGuardian',
      );
    });
    it('success - trusted updated', async () => {
      expect(await distributor.canUpdateMerkleRoot(bob.address)).to.be.equal(0);
      const receipt = await (await distributor.connect(guardian).toggleTrusted(bob.address)).wait();
      expect(await distributor.canUpdateMerkleRoot(bob.address)).to.be.equal(1);
      inReceipt(receipt, 'TrustedToggled', {
        eoa: bob.address,
        trust: true,
      });
    });
    it('success - trusted updated and then removed', async () => {
      await (await distributor.connect(guardian).toggleTrusted(bob.address)).wait();
      const receipt = await (await distributor.connect(guardian).toggleTrusted(bob.address)).wait();
      inReceipt(receipt, 'TrustedToggled', {
        eoa: bob.address,
        trust: false,
      });
      expect(await distributor.canUpdateMerkleRoot(bob.address)).to.be.equal(0);
    });
  });
  describe('toggleOnlyOperatorCanClaim', () => {
    it('reverts - not authorized', async () => {
      await expect(distributor.connect(alice).toggleOnlyOperatorCanClaim(bob.address)).to.be.revertedWithCustomError(
        distributor,
        'NotTrusted',
      );
    });
    it('success - whitelist updated - call by guardian', async () => {
      expect(await distributor.onlyOperatorCanClaim(bob.address)).to.be.equal(0);
      const receipt = await (await distributor.connect(guardian).toggleOnlyOperatorCanClaim(bob.address)).wait();
      expect(await distributor.onlyOperatorCanClaim(bob.address)).to.be.equal(1);
      inReceipt(receipt, 'OperatorClaimingToggled', {
        user: bob.address,
        isEnabled: true,
      });
    });
    it('success - whitelist updated - call by user', async () => {
      await (await distributor.connect(bob).toggleOnlyOperatorCanClaim(bob.address)).wait();
      expect(await distributor.onlyOperatorCanClaim(bob.address)).to.be.equal(1);
      const receipt = await (await distributor.connect(bob).toggleOnlyOperatorCanClaim(bob.address)).wait();
      expect(await distributor.onlyOperatorCanClaim(bob.address)).to.be.equal(0);
      inReceipt(receipt, 'OperatorClaimingToggled', {
        user: bob.address,
        isEnabled: false,
      });
    });
  });
  describe('toggleOperator', () => {
    it('reverts - not authorized', async () => {
      await expect(distributor.connect(alice).toggleOperator(bob.address, alice.address)).to.be.revertedWithCustomError(
        distributor,
        'NotTrusted',
      );
    });
    it('success - whitelist updated - call by guardian', async () => {
      expect(await distributor.operators(bob.address, alice.address)).to.be.equal(0);
      const receipt = await (await distributor.connect(guardian).toggleOperator(bob.address, alice.address)).wait();
      expect(await distributor.operators(bob.address, alice.address)).to.be.equal(1);
      inReceipt(receipt, 'OperatorToggled', {
        user: bob.address,
        operator: alice.address,
        isWhitelisted: true,
      });
    });
    it('success - whitelist updated - call by user', async () => {
      await (await distributor.connect(guardian).toggleOperator(bob.address, alice.address)).wait();
      expect(await distributor.operators(bob.address, alice.address)).to.be.equal(1);
      const receipt = await (await distributor.connect(bob).toggleOperator(bob.address, alice.address)).wait();
      expect(await distributor.operators(bob.address, alice.address)).to.be.equal(0);
      inReceipt(receipt, 'OperatorToggled', {
        user: bob.address,
        operator: alice.address,
        isWhitelisted: false,
      });
    });
  });
  describe('recoverERC20', () => {
    it('reverts - not guardian', async () => {
      await expect(
        distributor.connect(alice).recoverERC20(angle.address, bob.address, parseEther('1')),
      ).to.be.revertedWithCustomError(distributor, 'NotGovernorOrGuardian');
    });
    it('reverts - insufficient amount in contract', async () => {
      await expect(distributor.connect(guardian).recoverERC20(angle.address, bob.address, parseEther('1'))).to.be
        .reverted;
    });
    it('success - amount received', async () => {
      await angle.mint(distributor.address, parseEther('2'));
      const receipt = await (
        await distributor.connect(guardian).recoverERC20(angle.address, bob.address, parseEther('0.5'))
      ).wait();
      inReceipt(receipt, 'Recovered', {
        token: angle.address,
        to: bob.address,
        amount: parseEther('0.5'),
      });
      expect(await angle.balanceOf(bob.address)).to.be.equal(parseEther('0.5'));
      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('1.5'));
    });
  });
  describe('updateTree', () => {
    it('reverts - not trusted', async () => {
      await expect(distributor.connect(alice).updateTree(merkleTree)).to.be.revertedWithCustomError(
        distributor,
        'NotTrusted',
      );
    });
    it('reverts - when there is an ongoing dispute', async () => {
      await distributor.connect(guardian).setDisputePeriod(86400);
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await angle.mint(alice.address, parseEther('1.3'));
      await angle.connect(alice).approve(distributor.address, parseEther('1'));
      await distributor.connect(alice).disputeTree('I do not like it');
      await expect(distributor.connect(alice).updateTree(merkleTree)).to.be.revertedWithCustomError(
        distributor,
        'NotTrusted',
      );
    });
    it('success - from a governance address', async () => {
      expect(await distributor.getMerkleRoot()).to.be.equal(emptyBytes);
      const receipt = await (await distributor.connect(guardian).updateTree(merkleTree)).wait();
      inReceipt(receipt, 'TreeUpdated', {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH'),
      });
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(emptyBytes);
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(emptyBytes);
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
    });
    it('success - from a governance address and successive update', async () => {
      expect(await distributor.getMerkleRoot()).to.be.equal(emptyBytes);
      await distributor.connect(guardian).updateTree(merkleTree);
      const merkleTree2 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      };
      const receipt = await (await distributor.connect(guardian).updateTree(merkleTree2)).wait();
      inReceipt(receipt, 'TreeUpdated', {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      });
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_2'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
    });
    it('success - from a trusted address', async () => {
      await distributor.connect(guardian).toggleTrusted(bob.address);
      const receipt = await (await distributor.connect(bob).updateTree(merkleTree)).wait();
      inReceipt(receipt, 'TreeUpdated', {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH'),
      });
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
    });
    it('success - from a trusted address and successive update', async () => {
      await distributor.connect(guardian).toggleTrusted(bob.address);
      await distributor.connect(bob).updateTree(merkleTree);
      const merkleTree2 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      };
      const receipt = await (await distributor.connect(bob).updateTree(merkleTree2)).wait();
      inReceipt(receipt, 'TreeUpdated', {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      });
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_2'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
    });
    it('success - when from a trusted address and with dispute periods', async () => {
      await distributor.connect(guardian).toggleTrusted(bob.address);
      await distributor.connect(bob).updateTree(merkleTree);
      const merkleTree2 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      };
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      await distributor.connect(guardian).setDisputePeriod(86400);
      await increaseTime(86400);
      await distributor.connect(bob).updateTree(merkleTree2);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_2'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
      await increaseTime(86400);
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      const merkleTree3 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_3'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_3'),
      };
      await distributor.connect(bob).updateTree(merkleTree3);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_3'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_3'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_2'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
      // Updating the tree should work for the guardian but not for Bob
      const merkleTree4 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_4'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_4'),
      };
      // In this case updateTree
      await expect(distributor.connect(bob).updateTree(merkleTree4)).to.be.revertedWithCustomError(
        distributor,
        'NotTrusted',
      );
      await distributor.connect(guardian).updateTree(merkleTree4);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_4'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_4'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_3'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_3'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_3'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
    });
  });
  describe('disputeTree', () => {
    it('reverts - non allowance', async () => {
      await distributor.connect(guardian).setDisputePeriod(86400);
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await expect(distributor.connect(alice).disputeTree('I do not like it')).to.be.revertedWith(
        'ERC20: insufficient allowance',
      );
      await angle.mint(alice.address, parseEther('1'));
      await angle.connect(alice).approve(distributor.address, parseEther('0.9'));
      await expect(distributor.connect(alice).disputeTree('I do not like it')).to.be.revertedWith(
        'ERC20: insufficient allowance',
      );
    });
    it('reverts - no dispute period', async () => {
      await expect(distributor.connect(alice).disputeTree('I do not like it')).to.be.revertedWithCustomError(
        distributor,
        'InvalidDispute',
      );
    });
    it('success - dispute created', async () => {
      await distributor.connect(guardian).setDisputePeriod(86400);
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await angle.mint(alice.address, parseEther('1.3'));
      await angle.connect(alice).approve(distributor.address, parseEther('1'));
      const receipt = await (await distributor.connect(alice).disputeTree('I do not like it')).wait();
      inReceipt(receipt, 'Disputed', {
        reason: 'I do not like it',
      });
      expect(await distributor.disputer()).to.be.equal(alice.address);
    });
  });
  describe('resolveDispute', () => {
    it('reverts - non governor or guardian or not dispute', async () => {
      await expect(distributor.connect(alice).resolveDispute(false)).to.be.revertedWithCustomError(
        distributor,
        'NotGovernorOrGuardian',
      );
      await expect(distributor.connect(guardian).resolveDispute(false)).to.be.revertedWithCustomError(
        distributor,
        'NoDispute',
      );
    });
    it('success - invalid resolution', async () => {
      await distributor.connect(guardian).setDisputePeriod(86400);
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await angle.mint(alice.address, parseEther('1.3'));
      await angle.connect(alice).approve(distributor.address, parseEther('1'));
      await distributor.connect(alice).disputeTree('I do not like it');
      expect(await distributor.disputer()).to.be.equal(alice.address);
      const receipt = await (await distributor.connect(guardian).resolveDispute(false)).wait();
      inReceipt(receipt, 'DisputeResolved', {
        valid: false,
      });
      expect(await distributor.disputer()).to.be.equal(ZERO_ADDRESS);
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
      expect(await angle.balanceOf(guardian.address)).to.be.equal(parseEther('1'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('0.3'));
    });
    it('success - valid resolution', async () => {
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await distributor.connect(guardian).setDisputePeriod(86400);
      const merkleTree2 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      };
      await distributor.connect(guardian).updateTree(merkleTree2);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_2'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      await angle.mint(alice.address, parseEther('1.3'));
      await angle.connect(alice).approve(distributor.address, parseEther('1'));
      await distributor.connect(alice).disputeTree('I do not like it');
      expect(await distributor.disputer()).to.be.equal(alice.address);
      const receipt = await (await distributor.connect(guardian).resolveDispute(true)).wait();
      inReceipt(receipt, 'DisputeResolved', {
        valid: true,
      });
      inReceipt(receipt, 'TreeUpdated', {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH'),
      });
      expect(await distributor.disputer()).to.be.equal(ZERO_ADDRESS);
      expect(await angle.balanceOf(guardian.address)).to.be.equal(parseEther('0'));
      expect(await angle.balanceOf(alice.address)).to.be.equal(parseEther('1.3'));
      expect(await distributor.lastTreeUpdate()).to.be.equal(0);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
    });
  });
  describe('revokeTree', () => {
    it('reverts - not guardian', async () => {
      await expect(distributor.connect(alice).revokeTree()).to.be.revertedWithCustomError(
        distributor,
        'NotGovernorOrGuardian',
      );
    });
    it('reverts - when there is a live dispute', async () => {
      await distributor.connect(guardian).setDisputePeriod(86400);
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await angle.mint(alice.address, parseEther('1.3'));
      await angle.connect(alice).approve(distributor.address, parseEther('1'));
      await distributor.connect(alice).disputeTree('I do not like it');
      await expect(distributor.connect(guardian).revokeTree()).to.be.revertedWithCustomError(
        distributor,
        'UnresolvedDispute',
      );
    });
    it('success - when there is a tree that is live', async () => {
      await distributor.connect(guardian).toggleTrusted(bob.address);
      await distributor.connect(bob).updateTree(merkleTree);
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
      const receipt = await (await distributor.connect(guardian).revokeTree()).wait();
      inReceipt(receipt, 'TreeUpdated', {
        merkleRoot: emptyBytes,
        ipfsHash: emptyBytes,
      });
      expect(await distributor.lastTreeUpdate()).to.be.equal(0);
      expect((await distributor.tree()).merkleRoot).to.be.equal(emptyBytes);
      expect((await distributor.tree()).ipfsHash).to.be.equal(emptyBytes);
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(emptyBytes);
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(emptyBytes);
      expect(await distributor.getMerkleRoot()).to.be.equal(emptyBytes);
    });
    it('success - when there is a tree that is pending', async () => {
      await distributor.connect(guardian).toggleTrusted(bob.address);
      await distributor.connect(bob).updateTree(merkleTree);
      const merkleTree2 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      };
      await distributor.connect(bob).updateTree(merkleTree2);
      expect(await distributor.lastTreeUpdate()).to.be.equal(await latestTime());
      await distributor.connect(guardian).setDisputePeriod(86400);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_2'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_2'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      const receipt = await (await distributor.connect(guardian).revokeTree()).wait();
      inReceipt(receipt, 'TreeUpdated', {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH'),
      });
      expect(await distributor.lastTreeUpdate()).to.be.equal(0);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      const merkleTree3 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_3'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_3'),
      };
      await distributor.connect(bob).updateTree(merkleTree3);
      expect((await distributor.tree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_3'));
      expect((await distributor.tree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH_3'));
      expect((await distributor.lastTree()).merkleRoot).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      expect((await distributor.lastTree()).ipfsHash).to.be.equal(web3.utils.keccak256('IPFS_HASH'));
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT'));
      await increaseTime(86400);
      expect(await distributor.getMerkleRoot()).to.be.equal(web3.utils.keccak256('MERKLE_ROOT_3'));
    });
  });
  describe('setDisputePeriod', () => {
    it('reverts - non guardian', async () => {
      await expect(distributor.connect(alice).setDisputePeriod(10)).to.be.revertedWithCustomError(
        distributor,
        'NotGovernorOrGuardian',
      );
    });
    it('reverts - invalid param', async () => {
      await expect(distributor.connect(guardian).setDisputePeriod(parseUnits('1', 14))).to.be.revertedWithCustomError(
        distributor,
        'InvalidParam',
      );
    });
    it('success - dispute period updated', async () => {
      const receipt = await (await distributor.connect(guardian).setDisputePeriod(86400)).wait();
      expect(await distributor.disputePeriod()).to.be.equal(86400);
      inReceipt(receipt, 'DisputePeriodUpdated', {
        _disputePeriod: 86400,
      });
    });
  });
  describe('setDisputeToken', () => {
    it('reverts - non guardian', async () => {
      await expect(distributor.connect(alice).setDisputeToken(alice.address)).to.be.revertedWithCustomError(
        distributor,
        'NotGovernorOrGuardian',
      );
    });
    it('success - dispute amount updated', async () => {
      const receipt = await (await distributor.connect(guardian).setDisputeToken(angle.address)).wait();
      inReceipt(receipt, 'DisputeTokenUpdated', {
        _disputeToken: angle.address,
      });
      expect(await distributor.disputeToken()).to.be.equal(angle.address);
    });
    it('reverts - when ongoing dispute', async () => {
      await distributor.connect(guardian).setDisputePeriod(86400);
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await angle.mint(alice.address, parseEther('1.3'));
      await angle.connect(alice).approve(distributor.address, parseEther('1'));
      await distributor.connect(alice).disputeTree('I do not like it');
      await expect(distributor.connect(guardian).setDisputeToken(alice.address)).to.be.revertedWithCustomError(
        distributor,
        'UnresolvedDispute',
      );
    });
  });
  describe('setDisputeAmount', () => {
    it('reverts - non guardian', async () => {
      await expect(distributor.connect(alice).setDisputeAmount(parseEther('0.33'))).to.be.revertedWithCustomError(
        distributor,
        'NotGovernorOrGuardian',
      );
    });
    it('success - dispute amount updated', async () => {
      const receipt = await (await distributor.connect(guardian).setDisputeAmount(parseEther('0.33'))).wait();
      inReceipt(receipt, 'DisputeAmountUpdated', {
        _disputeAmount: parseEther('0.33'),
      });
      expect(await distributor.disputeAmount()).to.be.equal(parseEther('0.33'));
    });
    it('success - dispute amount updated', async () => {
      await distributor.connect(guardian).setDisputePeriod(86400);
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputeToken(angle.address);
      await distributor.connect(guardian).setDisputeAmount(parseEther('1'));
      await angle.mint(alice.address, parseEther('1.3'));
      await angle.connect(alice).approve(distributor.address, parseEther('1'));
      await distributor.connect(alice).disputeTree('I do not like it');
      await expect(distributor.connect(guardian).setDisputeAmount(parseEther('1.1'))).to.be.revertedWithCustomError(
        distributor,
        'UnresolvedDispute',
      );
    });
  });

  describe('claim', () => {
    it('reverts - invalid length', async () => {
      await expect(
        distributor.claim(
          [alice.address, bob.address],
          [angle.address],
          [parseEther('1')],
          [[web3.utils.keccak256('test')]],
        ),
      ).to.be.revertedWithCustomError(distributor, 'InvalidLengths');
      await expect(
        distributor.claim(
          [alice.address],
          [angle.address, angle.address],
          [parseEther('1')],
          [[web3.utils.keccak256('test')]],
        ),
      ).to.be.revertedWithCustomError(distributor, 'InvalidLengths');
      await expect(
        distributor.claim(
          [alice.address],
          [angle.address],
          [parseEther('1'), parseEther('1')],
          [[web3.utils.keccak256('test')]],
        ),
      ).to.be.revertedWithCustomError(distributor, 'InvalidLengths');
      await expect(
        distributor.claim(
          [alice.address],
          [angle.address],
          [parseEther('1')],
          [[web3.utils.keccak256('test')], [web3.utils.keccak256('test')]],
        ),
      ).to.be.revertedWithCustomError(distributor, 'InvalidLengths');
      await expect(
        distributor.claim([], [angle.address], [parseEther('1')], [[web3.utils.keccak256('test')]]),
      ).to.be.revertedWithCustomError(distributor, 'InvalidLengths');
    });
    it('reverts - root is zero', async () => {
      await distributor.connect(guardian).updateTree({ merkleRoot: constants.HashZero, ipfsHash: constants.HashZero });
      await expect(
        distributor.claim([alice.address], [angle.address], [parseEther('1')], [[web3.utils.keccak256('test')]]),
      ).to.be.revertedWithCustomError(distributor, 'InvalidUninitializedRoot');
    });
    it('reverts - invalid proof', async () => {
      await distributor.connect(guardian).updateTree({ merkleRoot: keccak256('0x1F'), ipfsHash: constants.HashZero });
      await expect(
        distributor.claim([alice.address], [angle.address], [parseEther('1')], [[web3.utils.keccak256('test')]]),
      ).to.be.revertedWithCustomError(distributor, 'InvalidProof');
    });
    it('reverts - small proof on one token but no token balance', async () => {
      const elements = [];
      const file = {
        '0x3931C80BF7a911fcda8b684b23A433D124b59F06': parseEther('1'),
        '0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002': parseEther('0.5'),
      };
      const fileProcessed = file as { [name: string]: BigNumber };
      const keys = Object.keys(fileProcessed);
      for (const key in keys) {
        const bytesPassed = ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256'],
          [keys[key], angle.address, fileProcessed[keys[key]]],
        );
        const hash = web3.utils.keccak256(bytesPassed);
        elements.push(hash);
      }

      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      await angle.mint(distributor.address, 10000);
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);

      await expect(
        distributor.claim(['0x3931C80BF7a911fcda8b684b23A433D124b59F06'], [angle.address], [parseEther('1')], [proof]),
      ).to.be.reverted;
    });
    it('reverts - whitelist', async () => {
      const elements = [];
      const file = {
        '0x3931C80BF7a911fcda8b684b23A433D124b59F06': parseEther('1'),
        '0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002': parseEther('0.5'),
      };
      const fileProcessed = file as { [name: string]: BigNumber };
      const keys = Object.keys(fileProcessed);
      for (const key in keys) {
        const bytesPassed = ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256'],
          [keys[key], angle.address, fileProcessed[keys[key]]],
        );
        const hash = web3.utils.keccak256(bytesPassed);
        elements.push(hash);
      }
      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      await angle.mint(distributor.address, parseEther('10'));
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);

      await (
        await distributor.connect(guardian).toggleOnlyOperatorCanClaim('0x3931C80BF7a911fcda8b684b23A433D124b59F06')
      ).wait();
      await expect(
        distributor
          .connect(bob)
          .claim(['0x3931C80BF7a911fcda8b684b23A433D124b59F06'], [angle.address], [parseEther('1')], [proof]),
      ).to.be.revertedWithCustomError(distributor, 'NotWhitelisted');
    });
    it('success - whitelist', async () => {
      const elements = [];
      const file = {
        '0x3931C80BF7a911fcda8b684b23A433D124b59F06': parseEther('1'),
        '0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002': parseEther('0.5'),
      };
      const fileProcessed = file as { [name: string]: BigNumber };
      const keys = Object.keys(fileProcessed);
      for (const key in keys) {
        const bytesPassed = ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256'],
          [keys[key], angle.address, fileProcessed[keys[key]]],
        );
        const hash = web3.utils.keccak256(bytesPassed);
        elements.push(hash);
      }
      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      await angle.mint(distributor.address, parseEther('10'));
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);

      await (
        await distributor.connect(guardian).toggleOnlyOperatorCanClaim('0x3931C80BF7a911fcda8b684b23A433D124b59F06')
      ).wait();
      await (
        await distributor.connect(guardian).toggleOperator('0x3931C80BF7a911fcda8b684b23A433D124b59F06', bob.address)
      ).wait();
      const receipt = await (
        await distributor
          .connect(bob)
          .claim(['0x3931C80BF7a911fcda8b684b23A433D124b59F06'], [angle.address], [parseEther('1')], [proof])
      ).wait();
      inReceipt(receipt, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: angle.address,
        amount: parseEther('1'),
      });
      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('9'));
      expect(await angle.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('1'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address)).amount,
      ).to.be.equal(parseEther('1'));
    });
    it('success - small proof on one token and token balance', async () => {
      const elements = [];
      const file = {
        '0x3931C80BF7a911fcda8b684b23A433D124b59F06': parseEther('1'),
        '0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002': parseEther('0.5'),
      };
      const fileProcessed = file as { [name: string]: BigNumber };
      const keys = Object.keys(fileProcessed);
      for (const key in keys) {
        const bytesPassed = ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256'],
          [keys[key], angle.address, fileProcessed[keys[key]]],
        );
        const hash = web3.utils.keccak256(bytesPassed);
        elements.push(hash);
      }
      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      await angle.mint(distributor.address, parseEther('10'));
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);

      const receipt = await (
        await distributor.claim(
          ['0x3931C80BF7a911fcda8b684b23A433D124b59F06'],
          [angle.address],
          [parseEther('1')],
          [proof],
        )
      ).wait();
      inReceipt(receipt, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: angle.address,
        amount: parseEther('1'),
      });
      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('9'));
      expect(await angle.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('1'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address)).amount,
      ).to.be.equal(parseEther('1'));
    });
    it('success - small proof on one token for different addresses', async () => {
      const elements = [];
      const file = {
        '0x3931C80BF7a911fcda8b684b23A433D124b59F06': parseEther('1'),
        '0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002': parseEther('0.5'),
      };
      const fileProcessed = file as { [name: string]: BigNumber };
      const keys = Object.keys(fileProcessed);
      for (const key in keys) {
        const bytesPassed = ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256'],
          [keys[key], angle.address, fileProcessed[keys[key]]],
        );
        const hash = web3.utils.keccak256(bytesPassed);
        elements.push(hash);
      }
      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      const proof2 = merkleTreeLib.getHexProof(elements[1]);
      await angle.mint(distributor.address, parseEther('10'));
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);

      const receipt = await (
        await distributor.claim(
          ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', '0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002'],
          [angle.address, angle.address],
          [parseEther('1'), parseEther('0.5')],
          [proof, proof2],
        )
      ).wait();
      inReceipt(receipt, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: angle.address,
        amount: parseEther('1'),
      });
      inReceipt(receipt, 'Claimed', {
        user: '0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002',
        token: angle.address,
        amount: parseEther('0.5'),
      });
      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('8.5'));
      expect(await angle.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('1'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address)).amount,
      ).to.be.equal(parseEther('1'));
      expect(await angle.balanceOf('0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002')).to.be.equal(parseEther('0.5'));
      expect(
        (await distributor.claimed('0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002', angle.address)).amount,
      ).to.be.equal(parseEther('0.5'));
    });

    it('success - small proof on different tokens for the same address', async () => {
      const elements = [];
      const bytesPassed1 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address, parseEther('1')],
      );
      const hash = web3.utils.keccak256(bytesPassed1);
      elements.push(hash);
      const agEUR = (await new MockToken__factory(deployer).deploy('agEUR', 'agEUR', 18)) as MockToken;
      const bytesPassed2 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', agEUR.address, parseEther('0.5')],
      );
      elements.push(web3.utils.keccak256(bytesPassed2));

      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      const proof2 = merkleTreeLib.getHexProof(elements[1]);
      await angle.mint(distributor.address, parseEther('10'));
      await agEUR.mint(distributor.address, parseEther('0.5'));
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);

      const receipt = await (
        await distributor.claim(
          ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', '0x3931C80BF7a911fcda8b684b23A433D124b59F06'],
          [angle.address, agEUR.address],
          [parseEther('1'), parseEther('0.5')],
          [proof, proof2],
        )
      ).wait();
      inReceipt(receipt, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: angle.address,
        amount: parseEther('1'),
      });
      inReceipt(receipt, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: agEUR.address,
        amount: parseEther('0.5'),
      });
      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('9'));
      expect(await angle.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('1'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address)).amount,
      ).to.be.equal(parseEther('1'));
      expect(await agEUR.balanceOf(distributor.address)).to.be.equal(parseEther('0'));
      expect(await agEUR.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('0.5'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', agEUR.address)).amount,
      ).to.be.equal(parseEther('0.5'));
    });
    it('success - two claims on the same token by the same address', async () => {
      let elements = [];
      const bytesPassed1 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address, parseEther('1')],
      );
      elements.push(web3.utils.keccak256(bytesPassed1));
      const agEUR = (await new MockToken__factory(deployer).deploy('agEUR', 'agEUR', 18)) as MockToken;
      const bytesPassed2 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', agEUR.address, parseEther('0.5')],
      );
      elements.push(web3.utils.keccak256(bytesPassed2));

      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      await angle.mint(distributor.address, parseEther('10'));
      await agEUR.mint(distributor.address, parseEther('0.5'));
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);

      // Doing first claim
      const receipt = await (
        await distributor.claim(
          ['0x3931C80BF7a911fcda8b684b23A433D124b59F06'],
          [angle.address],
          [parseEther('1')],
          [proof],
        )
      ).wait();
      inReceipt(receipt, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: angle.address,
        amount: parseEther('1'),
      });

      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('9'));
      expect(await angle.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('1'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address)).amount,
      ).to.be.equal(parseEther('1'));
      // Updating Merkle root after second claim
      elements = [];
      // Now the person can claim 2 additional tokens
      const bytesPassed3 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address, parseEther('3')],
      );
      elements.push(web3.utils.keccak256(bytesPassed3));
      const bytesPassed4 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', agEUR.address, parseEther('0.5')],
      );
      elements.push(web3.utils.keccak256(bytesPassed4));
      const merkleTreeLib2 = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root2 = merkleTreeLib2.getHexRoot();
      const proof2 = merkleTreeLib2.getHexProof(elements[0]);
      merkleTree.merkleRoot = root2;
      await distributor.connect(guardian).updateTree(merkleTree);
      const receipt2 = await (
        await distributor.claim(
          ['0x3931C80BF7a911fcda8b684b23A433D124b59F06'],
          [angle.address],
          [parseEther('3')],
          [proof2],
        )
      ).wait();
      inReceipt(receipt2, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: angle.address,
        amount: parseEther('2'),
      });

      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('7'));
      expect(await angle.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('3'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address)).amount,
      ).to.be.equal(parseEther('3'));
    });
    it('success - claims on an old Merkle root but not on the new one after an update', async () => {
      let elements = [];
      const bytesPassed1 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address, parseEther('1')],
      );
      elements.push(web3.utils.keccak256(bytesPassed1));
      const agEUR = (await new MockToken__factory(deployer).deploy('agEUR', 'agEUR', 18)) as MockToken;
      const bytesPassed2 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', agEUR.address, parseEther('0.5')],
      );
      elements.push(web3.utils.keccak256(bytesPassed2));

      const leaf = elements[0];
      const merkleTreeLib = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root = merkleTreeLib.getHexRoot();
      const proof = merkleTreeLib.getHexProof(leaf);
      await angle.mint(distributor.address, parseEther('10'));
      await agEUR.mint(distributor.address, parseEther('0.5'));
      merkleTree.merkleRoot = root;
      await distributor.connect(guardian).updateTree(merkleTree);
      await distributor.connect(guardian).setDisputePeriod(86400);
      const merkleTree2 = {
        merkleRoot: web3.utils.keccak256('MERKLE_ROOT_2'),
        ipfsHash: web3.utils.keccak256('IPFS_HASH_2'),
      };
      await distributor.connect(guardian).updateTree(merkleTree2);

      // Claim is still correct
      const receipt = await (
        await distributor.claim(
          ['0x3931C80BF7a911fcda8b684b23A433D124b59F06'],
          [angle.address],
          [parseEther('1')],
          [proof],
        )
      ).wait();
      inReceipt(receipt, 'Claimed', {
        user: '0x3931C80BF7a911fcda8b684b23A433D124b59F06',
        token: angle.address,
        amount: parseEther('1'),
      });

      expect(await angle.balanceOf(distributor.address)).to.be.equal(parseEther('9'));
      expect(await angle.balanceOf('0x3931C80BF7a911fcda8b684b23A433D124b59F06')).to.be.equal(parseEther('1'));
      expect(
        (await distributor.claimed('0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address)).amount,
      ).to.be.equal(parseEther('1'));
      // Updating Merkle root after second claim
      elements = [];
      // Now the person can claim 2 additional tokens
      const bytesPassed3 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', angle.address, parseEther('3')],
      );
      elements.push(web3.utils.keccak256(bytesPassed3));
      const bytesPassed4 = ethers.utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256'],
        ['0x3931C80BF7a911fcda8b684b23A433D124b59F06', agEUR.address, parseEther('0.5')],
      );
      elements.push(web3.utils.keccak256(bytesPassed4));
      const merkleTreeLib2 = new MerkleTree(elements, web3.utils.keccak256, { hashLeaves: false, sortPairs: true });
      const root2 = merkleTreeLib2.getHexRoot();
      const proof2 = merkleTreeLib2.getHexProof(elements[0]);
      merkleTree.merkleRoot = root2;
      await distributor.connect(guardian).updateTree(merkleTree);
      // In this case new Merkle Tree is not effectively pushed

      await expect(
        distributor.claim(['0x3931C80BF7a911fcda8b684b23A433D124b59F06'], [angle.address], [parseEther('3')], [proof2]),
      ).to.be.reverted;
    });
  });
});
