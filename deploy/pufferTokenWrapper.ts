import { DistributionCreator__factory } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';
import { Distributor__factory, PufferPointTokenWrapper__factory, PufferPointTokenWrapper } from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  const couponName = 'PufferPointTokenWrapper';
  const distributionCreator = DistributionCreator__factory.connect('0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd', deployer)
  const pufferPoint = '0xe7Cf38728DB67e5D78A7855000fbEC177B20B649';
  const aglaMerkl = '0x8d652c6d4A8F3Db96Cd866C1a9220B1447F29898'
  const cliffDuration = 300;
  const core = await distributionCreator.core()

  console.log(`Deploying Coupon`);
  console.log('Starting with the implementation');
/*
  await deploy(`${couponName}_Implementation`, {
    contract: couponName,
    from: deployer.address,
    args: [],
    log: !argv.ci,
  });
*/
  const implementationAddress = (await ethers.getContract(`${couponName}_Implementation`)).address;

  console.log(`Successfully deployed the contract ${couponName} implementation at ${implementationAddress}`);

  // const distributorInterface = Distributor__factory.createInterface();

  await deploy(`${couponName}Test_Proxy`, {
  contract: 'ERC1967Proxy',
     from: deployer.address,
     args: [implementationAddress, "0x"],
     log: !argv.ci,
   });
   const wrapper = (await deployments.get(`${couponName}Test_Proxy`)).address;
   console.log(`Successfully deployed contract at the address ${wrapper}`);
   console.log('Initializing the contract');
   const contract = new ethers.Contract(
     wrapper,
     PufferPointTokenWrapper__factory.createInterface(),
     deployer,
   ) as PufferPointTokenWrapper;

   await contract.initialize(aglaMerkl,cliffDuration,core,distributionCreator.address);
 
  console.log(`Successfully deployed the wrapper for ${couponName}  at ${wrapper}`);
  console.log('');
};

func.tags = ['puffer'];
export default func;
