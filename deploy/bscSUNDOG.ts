import { DistributionCreator__factory } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';
import { Distributor__factory } from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  console.log(`Deploying TokenLocker`);

  await deploy(`bscSUNDOG`, {
    contract: 'bscSUNDOG',
    from: deployer.address,
    args: [],
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract(`bscSUNDOG`)).address;


  console.log(`Successfully deployed the contract bscSUNDOG at ${implementationAddress}`);
  console.log('');
};

func.tags = ['bscSUNDOG'];
export default func;
