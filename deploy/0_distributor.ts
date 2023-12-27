import { ChainId, CONTRACTS_ADDRESSES, registry } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

import { Distributor, Distributor__factory } from '../typechain';
const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  let core: string;
  core = '0xFD0DFC837Fe7ED19B23df589b6F6Da5a775F99E0';
  /*
  if (!network.live) {
    // If we're in mainnet fork, we're using the `CoreBorrow` address from mainnet
    core = registry(ChainId.MAINNET)?.Merkl?.CoreMerkl!;
  } else {
    // Otherwise, we're using the proxy admin address from the desired network
    core = registry(network.config.chainId as ChainId)?.Merkl?.CoreMerkl!;
  }
  */

  console.log('Let us get started with deployment');
  console.log(deployer.address);

  console.log('Now deploying Distributor');
  console.log('Starting with the implementation');
  /*
  await deploy('Distributor_Implementation_2', {
    contract: 'Distributor',
    from: deployer.address,
    log: !argv.ci,
  });
  */

  const implementationAddress = (await ethers.getContract('Distributor_Implementation_2')).address;

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
  await (await contract.connect(deployer).initialize(core)).wait();
  console.log('Contract successfully initialized');
  console.log('');
};

func.tags = ['distributor'];
// func.dependencies = ['mockCore'];
export default func;
