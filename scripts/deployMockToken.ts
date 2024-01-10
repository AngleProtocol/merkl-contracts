import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

import { MAX_UINT256 } from '../test/hardhat/utils/helpers';
import { MockToken__factory } from '../typechain';

async function main() {
  const { deployer } = await ethers.getNamedSigners();
  const distributorCreator = `TO_COMPLETE`;
  console.log(`DistributorCreator address ${distributorCreator}`);

  console.log(`Deploying MockToken with address ${deployer.address}...`);
  const MockToken = await new MockToken__factory(deployer).deploy('MockAngleReward', 'agReward', 18);
  // const MockToken = MockToken__factory.connect('0x84FB94595f9Aef81147cD4070a1564128A84bb7c', deployer);
  console.log(`...Deployed mock token at address ${MockToken.address} ✅`);

  console.log(`Minting MockToken to ${deployer.address}...`);
  await (
    await MockToken.mint(deployer.address, parseEther('1000000'), {
      gasLimit: 300_000,
      maxPriorityFeePerGas: 100e9,
      maxFeePerGas: 700e9,
    })
  ).wait();
  console.log(`...Minted mock token to address ${deployer.address} ✅`);

  console.log('Approving...');
  await (await MockToken.connect(deployer).approve(distributorCreator, MAX_UINT256)).wait();
  console.log(`...Approved reward manager ${distributorCreator} succesfully ✅`);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
