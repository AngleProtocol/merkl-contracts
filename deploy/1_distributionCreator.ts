import { ChainId, registry } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

import { DistributionCreator, DistributionCreator__factory } from '../typechain';
import { parseAmount } from '../utils/bignumber';
const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();
  let coreBorrow: string;
  const distributor = (await deployments.get('Distributor')).address;
  /**
   * TODO: change this before real deployment
   */
  coreBorrow = (await deployments.get('MockCoreBorrow')).address;
  /*
  if (!network.live) {
    // If we're in mainnet fork, we're using the `CoreBorrow` address from mainnet
    coreBorrow = (await deployments.get('MockCoreBorrow')).address;
  } else {
    // Otherwise, we're using the proxy admin address from the desired network
    coreBorrow = registry(network.config.chainId as ChainId)?.CoreBorrow!;
  }
  */

  console.log('Now deploying DistributionCreator');
  console.log('Starting with the implementation');

  await deploy('DistributionCreator_Implementation', {
    contract: 'DistributionCreator',
    from: deployer.address,
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract('DistributionCreator_Implementation')).address;

  console.log(`Successfully deployed the implementation for DistributionCreator at ${implementationAddress}`);
  console.log('');

  console.log('Now deploying the Proxy');

  await deploy('DistributionCreator', {
    contract: 'ERC1967Proxy',
    from: deployer.address,
    args: [implementationAddress, '0x'],
    log: !argv.ci,
  });

  const manager = (await deployments.get('DistributionCreator')).address;
  console.log(`Successfully deployed contract at the address ${manager}`);
  console.log('Initializing the contract');
  const contract = new ethers.Contract(
    manager,
    DistributionCreator__factory.createInterface(),
    deployer,
  ) as DistributionCreator;

  await (await contract.connect(deployer).initialize(coreBorrow, distributor, parseAmount.gwei('0.03'))).wait();
  console.log('Contract successfully initialized');
  console.log('');
  console.log(await contract.coreBorrow());
};

func.tags = ['distributionCreator'];
func.dependencies = ['distributor'];
export default func;