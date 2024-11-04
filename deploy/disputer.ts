import { ChainId, CONTRACTS_ADDRESSES, registry } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';
import * as readline from 'readline';
import { Wallet, Provider, Contract} from 'zksync-ethers';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';
import { Distributor, Distributor__factory } from '../typechain';
import { Interface, parseUnits } from 'ethers';

// load env file
import dotenv from 'dotenv';
dotenv.config();

const argv = yargs.env('').boolean('ci').parseSync();

// Before running this deployment, make sure that on borrow-contracts the ProxyAdminAngleLabs and CoreMerkl
// contracts were deployed with:
// - governor of CoreMerkl: AngleLabs address
// - guardian: the deployer address
// Admin of ProxyAdmin: AngleLabs multisig
const func: DeployFunction = async (hre) => {
  // Initialize the wallet.
  const wallet = new Wallet(process.env.DEPLOYER_PRIVATE_KEY!, new Provider(process.env.ETH_NODE_URI_ZKSYNC));

  // // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet);
  // hre.network.provider = new Provider(process.env.ETH_NODE_URI_ZKSYNC) as any;

  let core: string;
  // TODO: change the coreMerkl address to that of the desired chain
  // Merkl deployer: 0x9f76a95AA7535bb0893cf88A146396e00ed21A12


  let artifact = await deployer.loadArtifact('Disputer');
  let implem = await hre.deployer.deploy(artifact, ['0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701',[
    '0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e',
    '0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B',
    '0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA'
  ], '0xe117ed7Ef16d3c28fCBA7eC49AFAD77f451a6a21']);
  let implemAddress = await implem.getAddress();
  console.log(implemAddress)

  
  // console.log(`Successfully deployed the implementation for Distributor at ${implemAddress}`);
  // console.log('');
  
  // console.log('Now deploying the Proxy');

  // const dataInitialize = new Interface(artifact.abi).encodeFunctionData('initialize', [core]);
  // console.log(dataInitialize);
  // const artifactProxy = await deployer.loadArtifact('ERC1967Proxy');
  // // let proxy = await hre.deployer.deploy(artifactProxy, [implemAddress, '0x']);
  // let proxyAddress = '0xe117ed7Ef16d3c28fCBA7eC49AFAD77f451a6a21'
  // const distributorAddress = proxyAddress

  // let contract = new Contract(proxyAddress, artifact.abi, wallet);

  // // await (await contract.initialize(core)).wait();
  // await (await deployer.zkWallet.sendTransaction({to: proxyAddress, data: contract.interface.encodeFunctionData('initialize', [core])})).wait();

  // artifact = await deployer.loadArtifact('DistributionCreator');
  // let implem = await hre.deployer.deploy(artifact, []);
  // implemAddress = await implem.getAddress(); // 0x5D4B41b5049a3624814DdFc3f1271e3539EEb06f

  // let proxy = await hre.deployer.deploy(artifactProxy, [implemAddress, '0x']);
  // proxyAddress = await proxy.getAddress();

  // contract = new Contract(proxyAddress, artifact.abi, wallet);

  // // await (await contract.initialize(core, distributorAddress, parseUnits('0.03', 'gwei'))).wait();
  // await (await deployer.zkWallet.sendTransaction({to: proxyAddress, data: contract.interface.encodeFunctionData('initialize', [core, distributorAddress, parseUnits('0.03', 'gwei')])})).wait();

 
  console.log('Contract successfully initialized');
  console.log('');
};

func.tags = ['disputer'];
// func.dependencies = ['mockCore'];
export default func;