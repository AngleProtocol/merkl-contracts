import { ethers } from 'hardhat';
import { Disputer__factory } from '../typechain';
import { ChainId, registry } from '@angleprotocol/sdk';

async function main() {
  
  // Get the network to determine chainId
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;
  
  // Get AngleLabs address from registry
  const disputerAddress = "0x2f9EDc2c334D4D9316E540A7f7BF332cce0d90d1" // registry(chainId as ChainId)?.Disputer;

  const newOwner = registry(chainId as ChainId)?.AngleLabs;
  if (!newOwner) {
    throw new Error(`No AngleLabs address found for chain ${chainId}`);
  }

  console.log(`Transferring Disputer ownership to ${newOwner}...`);
  try {
    // Get the signer
    const [signer] = await ethers.getSigners();
    
    // Create contract instance
    const disputer = Disputer__factory.connect(disputerAddress, signer);

    // Transfer ownership
    const tx = await disputer.transferOwnership(newOwner);
    await tx.wait();

    console.log(`Successfully transferred Disputer ownership to ${newOwner}`);
  } catch (error) {
    console.error(`Failed to transfer Disputer ownership: ${error instanceof Error ? error.message : String(error)}`);
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });