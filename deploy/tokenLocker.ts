import { DistributionCreator__factory } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';
import { Distributor__factory } from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  console.log(`Deploying TokenLocker`);

  await deploy(`TokenLocker2`, {
    contract: 'TokenLocker',
    from: deployer.address,
    args: ['0x2Dd2290EabdB5654609352Cc267C9BAc82d01877', '0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B', 60*5, 'Locked slisBNB', 'LslisBNB'],
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract(`TokenLocker`)).address;


  console.log(`Successfully deployed the contract TokenLocker at ${implementationAddress}`);
  console.log('');
};

func.tags = ['locker'];
export default func;
