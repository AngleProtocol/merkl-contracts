import { ChainId, CONTRACTS_ADDRESSES, CoreBorrow, CoreBorrow__factory, registry } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';
import * as readline from 'readline';

import { Distributor, Distributor__factory } from '../typechain';
const argv = yargs.env('').boolean('ci').parseSync();

// Before running this deployment, make sure that on borrow-contracts the ProxyAdminAngleLabs and CoreMerkl
// contracts were deployed with:
// - governor of CoreMerkl: AngleLabs address
// - guardian: the deployer address
// Admin of ProxyAdmin: AngleLabs multisig
const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  let core: string;
  // TODO: change the coreMerkl address to that of the desired chain

  // core = '0x1746f9bb465d3747fe9C2CfE7759F4B871a06d3C';
  // const coreContract = new ethers.Contract(core, CoreBorrow__factory.createInterface(), deployer) as any;
  // if (await coreContract.GOVERNOR_ROLE()!= '0x7935bd0ae54bc31f548c14dba4d37c5c64b3f8ca900cb468fb8abd54d5894f55') throw 'Invalid Core Merkl'

  // if (deployer.address !== '0x9f76a95AA7535bb0893cf88A146396e00ed21A12') throw `Invalid deployer address: ${deployer.address}`;
  /*
  if (!network.live) {
    // If we're in mainnet fork, we're using the `CoreBorrow` address from mainnet
    core = registry(ChainId.MAINNET)?.Merkl?.CoreMerkl!;
  } else {
    // Otherwise, we're using the proxy admin address from the desired network
    core = registry(network.config.chainId as ChainId)?.Merkl?.CoreMerkl!;
  }
  */

  console.log('Let us get started with deployment, deploying with this address');
  console.log(deployer.address);

  console.log('Now deploying Distributor');
  console.log('Starting with the implementation');

  await deploy('Distributor_Implementation_V2_2', {
    contract: 'Distributor',
    from: deployer.address,
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract('Distributor_Implementation_V2_2')).address;
 
  // console.log(`Successfully deployed the implementation for Distributor at ${implementationAddress}`);
  // console.log('');
  
  // console.log('Now deploying the Proxy');

  // await deploy('Distributor', {
  //   contract: 'ERC1967Proxy',
  //   from: deployer.address,
  //   args: [implementationAddress, '0x'],
  //   log: !argv.ci,
  // });

  // const distributor = (await deployments.get('Distributor')).address;
  // console.log(`Successfully deployed contract at the address ${distributor}`);
  // console.log('Initializing the contract');
  // const contract = new ethers.Contract(distributor, Distributor__factory.createInterface(), deployer) as Distributor;
  // await (await contract.connect(deployer).initialize(core)).wait();
  // console.log('Contract successfully initialized');
  // console.log('');
};

func.tags = ['distributor'];
// func.dependencies = ['mockCore'];
export default func;
