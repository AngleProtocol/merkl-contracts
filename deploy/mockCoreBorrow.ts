import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

import { MockCoreBorrow, MockCoreBorrow__factory } from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();
  console.log('Deploying a MockCoreBorrow instance');
  await deploy('MockCoreBorrow', {
    contract: 'MockCoreBorrow',
    from: deployer.address,
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract('MockCoreBorrow')).address;

  const contract = new ethers.Contract(
    implementationAddress,
    MockCoreBorrow__factory.createInterface(),
    deployer,
  ) as MockCoreBorrow;
  console.log('Setting governors');
  await (await contract.connect(deployer).toggleGovernor(deployer.address)).wait();
  await (await contract.connect(deployer).toggleGuardian(deployer.address)).wait();
};

func.tags = ['mockCore'];
export default func;
