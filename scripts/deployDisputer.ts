import { ethers } from 'hardhat';
import { ChainId, registry } from '@angleprotocol/sdk';

async function main() {
  // Get the network to determine chainId
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;

  console.log(`Deploying Disputer on ${network.name.toString()} (chainId: ${chainId})...`);

  try {
    const distributor = registry(chainId as ChainId)?.Merkl?.Distributor;
    const owner = '0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701';
    const whitelist = [
      '0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e',
      '0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B',
      '0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA'
    ];

    if(!distributor || !owner) {
      throw new Error(`No distributor or deployer address found for chain ${chainId}`);
    }

    const {deployer} = await ethers.getNamedSigners();
    const Disputer = await ethers.getContractFactory('Disputer', deployer);
    const disputer = await Disputer.deploy(owner, whitelist, distributor);
    
    const disputerAddress = disputer.address;
    console.log(`Successfully deployed Disputer to: ${disputerAddress}`);
  } catch (error) {
    console.error(`Failed to deploy Disputer: ${error instanceof Error ? error.message : String(error)}`);
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });