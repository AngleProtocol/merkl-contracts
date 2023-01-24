import { expect } from 'chai';
import { BigNumber, BigNumberish, BytesLike, Contract, ContractFactory, Signer } from 'ethers';
import { parseUnits } from 'ethers/lib/utils';
import hre, { ethers } from 'hardhat';

import { ERC1967Proxy__factory, TransparentUpgradeableProxy__factory } from '../../../typechain';

const BASE_PARAMS = parseUnits('1', 'gwei');

async function getImpersonatedSigner(address: string): Promise<Signer> {
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [address],
  });

  const signer = await ethers.getSigner(address);

  return signer;
}

async function increaseTime(amount: number | string | BigNumberish): Promise<void> {
  await time.increase(amount);
}

async function resetTime(): Promise<void> {
  await resetFork();
}

async function resetFork(options?: { blockNumber?: number; jsonRpcUrl?: string }): Promise<void> {
  const jsonRpcUrl = hre.config.networks.hardhat.forking?.url || options?.jsonRpcUrl;

  const params: {
    forking?: { jsonRpcUrl: string; blockNumber?: number };
  } = {
    forking: jsonRpcUrl
      ? {
          jsonRpcUrl,
        }
      : undefined,
  };

  if (params.forking && options?.blockNumber) {
    params.forking.blockNumber = options.blockNumber;
  }

  await hre.network.provider.request({
    method: 'hardhat_reset',
    params: [params],
  });
}

async function setNextBlockTimestamp(time: number): Promise<void> {
  await hre.network.provider.request({
    method: 'evm_setNextBlockTimestamp',
    params: [time],
  });
}

async function latestTime(): Promise<number> {
  const { timestamp } = await ethers.provider.getBlock(await ethers.provider.getBlockNumber());

  return timestamp as number;
}

async function mine(): Promise<void> {
  await hre.network.provider.request({
    method: 'evm_mine',
  });
}

const ZERO_ADDRESS = ethers.constants.AddressZero;
const MAX_UINT256 = ethers.constants.MaxUint256;

const balance = {
  current: async (address: string): Promise<BigNumber> => {
    const balance = await ethers.provider.getBalance(address);
    return balance;
  },
};

const time = {
  latest: async (): Promise<number> => latestTime(),

  latestBlock: async (): Promise<number> => await ethers.provider.getBlockNumber(),

  increase: async (duration: number | string | BigNumberish): Promise<void> => {
    const durationBN = ethers.BigNumber.from(duration);

    if (durationBN.lt(ethers.constants.Zero)) throw Error(`Cannot increase time by a negative amount (${duration})`);

    await hre.network.provider.send('evm_increaseTime', [durationBN.toNumber()]);

    await hre.network.provider.send('evm_mine');
  },

  increaseTo: async (target: number | string | BigNumberish): Promise<void> => {
    const targetBN = ethers.BigNumber.from(target);

    const now = ethers.BigNumber.from(await time.latest());

    if (targetBN.lt(now)) throw Error(`Cannot increase current time (${now}) to a moment in the past (${target})`);
    const diff = targetBN.sub(now);
    return time.increase(diff);
  },

  advanceBlockTo: async (target: number | string | BigNumberish): Promise<void> => {
    target = ethers.BigNumber.from(target);

    const currentBlock = await time.latestBlock();
    const start = Date.now();
    let notified;
    if (target.lt(currentBlock))
      throw Error(`Target block #(${target}) is lower than current block #(${currentBlock})`);
    while (ethers.BigNumber.from(await time.latestBlock()).lt(target)) {
      if (!notified && Date.now() - start >= 5000) {
        notified = true;
        console.warn("You're advancing many blocks; this test may be slow.");
      }
      await time.advanceBlock();
    }
  },

  advanceBlock: async (): Promise<void> => {
    await hre.network.provider.send('evm_mine');
  },
};

// eslint-disable-next-line
async function deployUpgradeable(factory: ContractFactory, ...args: any[]): Promise<Contract> {
  const { deployer, proxyAdmin, alice } = await ethers.getNamedSigners();

  const Implementation = args.length === 0 ? await factory.deploy() : await factory.deploy(args[0], args[1]);
  const Proxy = await new TransparentUpgradeableProxy__factory(deployer).deploy(
    Implementation.address,
    proxyAdmin.address,
    '0x',
  );

  return new Contract(Proxy.address, factory.interface, alice);
}

async function deployUpgradeableUUPS(factory: ContractFactory, ...args: any[]): Promise<Contract> {
  const { deployer, alice } = await ethers.getNamedSigners();

  const Implementation = args.length === 0 ? await factory.deploy() : await factory.deploy(args[0], args[1]);
  const Proxy = await new ERC1967Proxy__factory(deployer).deploy(Implementation.address, '0x');

  return new Contract(Proxy.address, factory.interface, alice);
}

async function expectApproxDelta(actual: BigNumber, expected: BigNumber, delta: BigNumber): Promise<void> {
  const margin = expected.div(delta);
  if (actual.isNegative()) {
    expect(expected.gte(actual.add(margin))).to.be.true;
    expect(expected.lte(actual.sub(margin))).to.be.true;
  } else {
    expect(expected.lte(actual.add(margin))).to.be.true;
    expect(expected.gte(actual.sub(margin))).to.be.true;
  }
}

function expectApprox(value: BigNumberish, target: BigNumberish, error: number): void {
  expect(value).to.be.lt(
    BigNumber.from(target)
      .mul((100 + error) * 1e10)
      .div(100 * 1e10),
  );
  expect(value).to.be.gt(
    BigNumber.from(target)
      .mul((100 - error) * 1e10)
      .div(100 * 1e10),
  );
}

type MerkleTreeType = {
  merkleRoot: BytesLike;
  ipfsHash: BytesLike;
};

export {
  balance,
  BASE_PARAMS,
  deployUpgradeable,
  deployUpgradeableUUPS,
  expectApprox,
  expectApproxDelta,
  getImpersonatedSigner,
  increaseTime,
  latestTime,
  MAX_UINT256,
  MerkleTreeType,
  mine,
  resetFork,
  resetTime,
  setNextBlockTimestamp,
  time,
  ZERO_ADDRESS,
};
