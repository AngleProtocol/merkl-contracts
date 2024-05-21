import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';
import { ERC20, ERC20__factory, MockToken, MockToken__factory } from '../typechain';

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
    args: ["aglaMerkl","aglaMerkl", 6],
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract(implementationName)).address;

  const tokenContract = new ethers.Contract(implementationAddress, MockToken__factory.createInterface(), deployer) as MockToken;

  await tokenContract.mint(deployer.address, "1000000000000000000000000000");
  

  console.log(`Successfully deployed the contract ${implementationName} at ${implementationAddress}`);
  console.log('');
};

func.tags = ['aglaMerkl'];
export default func;
