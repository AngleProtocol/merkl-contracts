import { ChainId, CONTRACTS_ADDRESSES, registry } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

import { Distributor, Distributor__factory } from '../typechain';
const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();
  let coreBorrow: string;
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

  console.log('Let us get started with deployment');

  console.log('Now deploying Distributor');
  console.log('Starting with the implementation');

  await deploy('MerkleRootDistributor_Implementation', {
    contract: 'Distributor',
    from: deployer.address,
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract('MerkleRootDistributor_Implementation')).address;

  console.log(`Successfully deployed the implementation for Distributor at ${implementationAddress}`);
  console.log('');

  console.log('Now deploying the Proxy');

  await deploy('Distributor', {
    contract: 'ERC1967Proxy',
    from: deployer.address,
    args: [implementationAddress, '0x'],
    log: !argv.ci,
  });

  const distributor = (await deployments.get('Distributor')).address;
  console.log(`Successfully deployed contract at the address ${distributor}`);
  console.log('Initializing the contract');
  const contract = new ethers.Contract(distributor, Distributor__factory.createInterface(), deployer) as Distributor;
  await (await contract.connect(deployer).initialize(coreBorrow)).wait();
  console.log('Contract successfully initialized');
  console.log(await contract.coreBorrow());

  console.log('');
};

func.tags = ['distributor'];
// func.dependencies = ['mockCore'];
export default func;
