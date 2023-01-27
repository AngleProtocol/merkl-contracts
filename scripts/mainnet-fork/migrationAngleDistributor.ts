import { ChainId, CONTRACTS_ADDRESSES } from '@angleprotocol/sdk';
import { deployments, ethers, network, web3 } from 'hardhat';
import yargs from 'yargs';

import { deployUpgradeableUUPS, ZERO_ADDRESS } from '../../test/hardhat/utils/helpers';
import {
  AngleDistributor,
  AngleDistributor__factory,
  MerkleRewardManager,
  MerkleRewardManager__factory,
  MerklGaugeMiddleman,
  MerklGaugeMiddleman__factory,
  ProxyAdmin,
  ProxyAdmin__factory,
} from '../../typechain';
import { parseAmount } from '../../utils/bignumber';

const argv = yargs.env('').boolean('ci').parseSync();

async function main() {
  let manager: MerkleRewardManager;
  let angleDistributor: AngleDistributor;
  let middleman: MerklGaugeMiddleman;
  let params: any;

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();
  const proxyAdminAddress = CONTRACTS_ADDRESSES[ChainId.MAINNET].ProxyAdmin!;
  const governor = CONTRACTS_ADDRESSES[ChainId.MAINNET].Governor! as string;
  const coreBorrow = CONTRACTS_ADDRESSES[ChainId.MAINNET].CoreBorrow! as string;
  const distributor = CONTRACTS_ADDRESSES[ChainId.MAINNET].MerkleRootDistributor! as string;
  const angleDistributorAddress = CONTRACTS_ADDRESSES[ChainId.MAINNET].AngleDistributor! as string;
  const angleAddress = CONTRACTS_ADDRESSES[ChainId.MAINNET].ANGLE! as string;
  const agEURAddress = CONTRACTS_ADDRESSES[ChainId.MAINNET].agEUR! as string;
  const gaugeAddr = '0xEB7547a8a734b6fdDBB8Ce0C314a9E6485100a3C';

  params = {
    uniV3Pool: '0x735a26a57a0a0069dfabd41595a970faf5e1ee8b',
    token: angleAddress,
    positionWrappers: [],
    wrapperTypes: [],
    amount: parseAmount.gwei('100000'),
    propToken1: 4000,
    propToken2: 2000,
    propFees: 4000,
    outOfRangeIncentivized: 0,
    epochStart: 0,
    numEpoch: 168,
    boostedReward: 0,
    boostingAddress: ZERO_ADDRESS,
    rewardId: web3.utils.soliditySha3('TEST') as string,
  };

  await network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [governor],
  });
  await network.provider.send('hardhat_setBalance', [governor, '0x10000000000000000000000000000']);
  const governorSigner = await ethers.provider.getSigner(governor);

  console.log('First deploying implementation for distributor');
  await deploy('AngleDistributor_NewImplementation', {
    contract: 'AngleDistributor',
    from: deployer.address,
    log: !argv.ci,
  });
  console.log('Success');

  const distributorImplementationAddress = (await deployments.get('AngleDistributor_NewImplementation')).address;

  const contractProxyAdmin = new ethers.Contract(
    proxyAdminAddress,
    ProxyAdmin__factory.createInterface(),
    governorSigner,
  ) as ProxyAdmin;

  angleDistributor = new ethers.Contract(
    angleDistributorAddress,
    AngleDistributor__factory.createInterface(),
    governorSigner,
  ) as AngleDistributor;

  console.log('Now performing the upgrades');
  await (
    await contractProxyAdmin.connect(governorSigner).upgrade(angleDistributorAddress, distributorImplementationAddress)
  ).wait();
  console.log('Success');

  manager = (await deployUpgradeableUUPS(new MerkleRewardManager__factory(deployer))) as MerkleRewardManager;
  await manager.initialize(coreBorrow, distributor, parseAmount.gwei('0.1'));

  middleman = (await new MerklGaugeMiddleman__factory(deployer).deploy(coreBorrow)) as MerklGaugeMiddleman;

  console.log('Toggling signature whitelist');
  await (await manager.connect(governorSigner).toggleSigningWhitelist(middleman.address)).wait();
  await manager.connect(governorSigner).toggleTokenWhitelist(agEURAddress);
  // agEUR-USDC gauge address
  await middleman.connect(governorSigner).setGauge(gaugeAddr, params);
  await angleDistributor.connect(governorSigner).setDelegateGauge(gaugeAddr, middleman.address, true);

  // TODO increase time and then check ANGLE distribution
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
