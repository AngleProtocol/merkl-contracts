import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();
  let core: string;

  const implementationName = 'MockToken';

  console.log(`Now deploying ${implementationName}`);
  console.log('Starting with the implementation');

  await deploy(implementationName, {
    contract: implementationName,
    from: deployer.address,
    args: ["aglaMerkl","aglaMerkl",6],
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract(implementationName)).address;

  console.log(`Successfully deployed the contract ${implementationName} at ${implementationAddress}`);
  console.log('');
};

func.tags = ['aglaMerkl'];
export default func;
