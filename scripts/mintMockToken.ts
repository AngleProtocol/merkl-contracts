import { parseEther, parseUnits } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

import { MAX_UINT256 } from '../test/hardhat/utils/helpers';
import { MockToken__factory } from '../typechain';

async function main() {
  const { deployer } = await ethers.getNamedSigners();

  const MockToken = MockToken__factory.connect('0xC011882d0f7672D8942e7fE2248C174eeD640c8f', deployer);

  console.log(`Minting MockToken to ${deployer.address}...`);
  await (
    await MockToken.mint('0xFee2D4498085581DDE097b9924E4E3544682D767', parseUnits('100000', 18), {
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
