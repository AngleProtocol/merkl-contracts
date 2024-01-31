import { ChainId, CONTRACTS_ADDRESSES } from '@angleprotocol/sdk';
import { deployments, ethers, network, web3 } from 'hardhat';
import yargs from 'yargs';

import { deployUpgradeableUUPS, increaseTime, ZERO_ADDRESS } from '../../test/hardhat/utils/helpers';
import {
  DistributionCreator,
  DistributionCreator__factory,
  ERC20,
  ERC20__factory,
  MockMerklGaugeMiddleman,
  MockMerklGaugeMiddleman__factory,
  ProxyAdmin,
  ProxyAdmin__factory,
} from '../../typechain';
import { formatAmount, parseAmount } from '../../utils/bignumber';

const argv = yargs.env('').boolean('ci').parseSync();

async function main() {
  let manager: DistributionCreator;
  let middleman: MockMerklGaugeMiddleman;
  let angle: ERC20;
  let params: any;

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  const manager = new ethers.Contract(
    proxyAdminAddress,
    ProxyAdmin__factory.createInterface(),
    governorSigner,
  ) as ProxyAdmin;

  const newImplementation = await new DistributionCreator__factory(deployer).deploy();
  await manager.connect(governor).upgradeTo(newImplementation.address);

  const proxyAdminAddress = CONTRACTS_ADDRESSES[ChainId.MAINNET].ProxyAdmin!;
  const governor = CONTRACTS_ADDRESSES[ChainId.MAINNET].Governor! as string;
  const coreBorrow = CONTRACTS_ADDRESSES[ChainId.MAINNET].CoreBorrow! as string;
  const distributor = CONTRACTS_ADDRESSES[ChainId.MAINNET].Distributor! as string;
  const angleDistributorAddress = CONTRACTS_ADDRESSES[ChainId.MAINNET].AngleDistributor! as string;
  const angleAddress = CONTRACTS_ADDRESSES[ChainId.MAINNET].ANGLE! as string;
  const agEURAddress = '0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8';
  // agEUR-USDC gauge address
  const gaugeAddr = '0xEB7547a8a734b6fdDBB8Ce0C314a9E6485100a3C';

  params = {
    uniV3Pool: '0x735a26a57a0a0069dfabd41595a970faf5e1ee8b',
    token: angleAddress,
    positionWrappers: [],
    wrapperTypes: [],
    amount: parseAmount.gwei('100000'),
    propToken0: 4000,
    propToken1: 2000,
    propFees: 4000,
    isOutOfRangeIncentivized: 0,
    epochStart: 0,
    numEpoch: 168,
    boostedReward: 0,
    boostingAddress: ZERO_ADDRESS,
    rewardId: web3.utils.soliditySha3('TEST') as string,
    additionalData: web3.utils.soliditySha3('test2ng') as string,
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

  angle = new ethers.Contract(angleAddress, ERC20__factory.createInterface(), governorSigner) as ERC20;

  console.log('Now performing the upgrades');
  await (
    await contractProxyAdmin.connect(governorSigner).upgrade(angleDistributorAddress, distributorImplementationAddress)
  ).wait();
  console.log('Success');

  manager = (await deployUpgradeableUUPS(new MerkleRewardManager__factory(deployer))) as DistributionCreator;
  await manager.initialize(coreBorrow, distributor, parseAmount.gwei('0.1'));

  middleman = (await new MockMerklGaugeMiddleman__factory(deployer).deploy(coreBorrow)) as MockMerklGaugeMiddleman;

  await middleman.setAddresses(angleDistributorAddress, angleAddress, manager.address);

  console.log('Toggling signature whitelist');
  await (await manager.connect(governorSigner).toggleSigningWhitelist(middleman.address)).wait();
  console.log('Toggling token whitelist');
  await manager.connect(governorSigner).toggleTokenWhitelist(agEURAddress);

  console.log('Setting the gauge on the middleman');
  await middleman.connect(governorSigner).setGauge(gaugeAddr, params);
  console.log('Setting the middleman as a delegate for the gauge');
  await angleDistributor.connect(governorSigner).setDelegateGauge(gaugeAddr, middleman.address, true);
  console.log('Setting allowance');
  await middleman.connect(governorSigner).setAngleAllowance();
  console.log(middleman.address);

  await increaseTime(86400 * 7);

  const angleBalanceDistr = await angle.balanceOf(distributor);
  console.log(formatAmount.ether(angleBalanceDistr.toString()));
  await angleDistributor.connect(governorSigner).distributeReward(gaugeAddr);
  const angleBalanceDistr1 = await angle.balanceOf(distributor);
  console.log(formatAmount.ether(angleBalanceDistr1.toString()));
  await angleDistributor.connect(governorSigner).distributeReward(gaugeAddr);
  const angleBalanceDistr2 = await angle.balanceOf(distributor);
  console.log(formatAmount.ether(angleBalanceDistr2.toString()));
  await increaseTime(86400 * 7);
  await angleDistributor.connect(governorSigner).distributeReward(gaugeAddr);
  const angleBalanceDistr3 = await angle.balanceOf(distributor);
  console.log(formatAmount.ether(angleBalanceDistr3.toString()));
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
