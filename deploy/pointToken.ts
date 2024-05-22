import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();
  let core: string;

  const implementationName = 'PointToken';

  console.log(`Now deploying ${implementationName}`);
  console.log('Starting with the implementation');

  await deploy(implementationName, {
    contract: implementationName,
    from: deployer.address,
    args: ["Angle Prots","agProts", "0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701","0xFD0DFC837Fe7ED19B23df589b6F6Da5a775F99E0"],
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract(implementationName)).address;

  console.log(`Successfully deployed the contract ${implementationName} at ${implementationAddress}`);
  console.log('');
};

func.tags = ['pointToken'];
export default func;
