import { deployments, ethers } from 'hardhat';

import { Distributor, Distributor__factory } from '../typechain';
import { parseEther,parseUnits, getAddress } from 'ethers/lib/utils';
import { registry } from '@angleprotocol/sdk';

async function main() {
  let distributor: Distributor;
  const { deployer } = await ethers.getNamedSigners();
  const chainId = (await deployer.provider?.getNetwork())?.chainId;
  console.log('chainId', chainId)
  const distributorAddress = registry(chainId as unknown as number)?.Merkl?.Distributor // (await deployments.get('DistributionCreator')).address;

  if (!distributorAddress) {
    throw new Error('Manager address not found');
  }

  distributor = new ethers.Contract(
    distributorAddress,
    Distributor__factory.createInterface(),
    deployer,
  ) as Distributor;

  console.log('Toggling operator');
  
  const res = await (
    await distributor
      .connect(deployer)
      .toggleOperator('0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971','0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138')
  ).wait();

  await distributor
  .connect(deployer)
  .toggleOperator('0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec','0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138')
  
  console.log(res);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
