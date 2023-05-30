import { ChainId, registry } from '@angleprotocol/sdk';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

import { DistributionCreator, DistributionCreator__factory } from '../typechain';
import { parseAmount } from '../utils/bignumber';
const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, ethers, network }) => {
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();
  let core: string;

  /**
   * TODO: change for Polygon deployment to MerklGaugeMiddlemanPolygon
   */
  const implementationName = 'MerklGaugeMiddlemanPolygon';

  if (!network.live) {
    // If we're in mainnet fork, we're using the `CoreBorrow` address from mainnet
    core = registry(ChainId.MAINNET)?.Merkl?.CoreMerkl!;
  } else {
    // Otherwise, we're using the proxy admin address from the desired network
    core = registry(network.config.chainId as ChainId)?.Merkl?.CoreMerkl!;
  }

  console.log('Now deploying DistributionCreator');
  console.log('Starting with the implementation');

  await deploy(implementationName, {
    contract: implementationName,
    from: deployer.address,
    args: [core],
    log: !argv.ci,
  });

  const implementationAddress = (await ethers.getContract(implementationName)).address;

  console.log(`Successfully deployed the implementation for DistributionCreator at ${implementationAddress}`);
  console.log('');
};

func.tags = ['middleman'];
export default func;
