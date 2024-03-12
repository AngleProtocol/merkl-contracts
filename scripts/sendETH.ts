import { ethers} from 'hardhat';

import { parseEther } from 'ethers/lib/utils';

async function main() {
  const { deployer } = await ethers.getNamedSigners();

  await deployer.sendTransaction({
    to: '0x435046800Fb9149eE65159721A92cB7d50a7534b',
    value: parseEther('4.6')
  })

}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
