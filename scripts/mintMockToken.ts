import { parseEther, parseUnits } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

import { MAX_UINT256 } from '../test/hardhat/utils/helpers';
import { MockToken__factory } from '../typechain';

async function main() {
  const { deployer } = await ethers.getNamedSigners();

  const MockToken = MockToken__factory.connect('0xA7c167f58833c5e25848837f45A1372491A535eD', deployer);

  console.log(`Minting MockToken to ${deployer.address}...`);
  await (
    await MockToken.mint("0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701", parseUnits('100000', 6), {
      // gasLimit: 300_000,
      // maxPriorityFeePerGas: 100e9,
      // maxFeePerGas: 700e9,
    })
  ).wait();
  console.log(`...Minted mock token to address ${deployer.address} ✅`);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
