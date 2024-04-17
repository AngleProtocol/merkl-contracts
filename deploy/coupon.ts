import { DistributionCreator__factory } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';
import { Distributor__factory } from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  const couponName = 'RadiantCoupon';
  const distributionCreator = DistributionCreator__factory.connect('0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd', deployer)
  const core = await distributionCreator.core()

  console.log(`Deploying Coupon`);
  console.log('Starting with the implementation');

  await deploy(`${couponName}_Implementation`, {
    contract: couponName,
    from: deployer.address,
    args: [],
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract(`${couponName}_Implementation`)).address;

  console.log('Starting with the implementation');

  const distributorInterface = Distributor__factory.createInterface();

  await deploy(`${couponName}_Proxy`, {
    contract: 'ERC1967Proxy',
    from: deployer.address,
    args: [implementationAddress, distributorInterface.encodeFunctionData('initialize', [core])],
    log: !argv.ci,
  });

  console.log(`Successfully deployed the contract ${couponName} at ${implementationAddress}`);
  console.log('');
};

func.tags = ['coupon'];
export default func;
