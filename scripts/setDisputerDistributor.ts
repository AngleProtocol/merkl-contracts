import { ethers, network } from 'hardhat';
import { Disputer__factory } from '../typechain';
import { registry } from '@angleprotocol/sdk';

async function main() {
  console.log(`\nChecking Disputer on ${network.name} (chainId: ${network.config.chainId})...`);

  try {
    // Get addresses from SDK registry
    const Registry = registry(network.config.chainId as number);

    const distributorAddress =  Registry?.Merkl?.Distributor;
    const disputerAddress = "0x2f9EDc2c334D4D9316E540A7f7BF332cce0d90d1" // Registry?.Merkl?.Disputer;

    if (!distributorAddress || !disputerAddress) {
      throw new Error('Required addresses not provided');
    }

    // Get current distributor from Disputer contract
    const signers = await ethers.getSigners();
    const deployer = signers[0];
    console.log(`Network: ${network.name}`);
    console.log('Deployer address:', await deployer.getAddress());
    console.log(`Expected distributor: ${distributorAddress}`);

    const disputer = Disputer__factory.connect(
      disputerAddress,
      deployer
    );
    const currentDistributor = await disputer.distributor();

    console.log(`Current distributor: ${currentDistributor}`);

    if (currentDistributor.toLowerCase() !== distributorAddress?.toLowerCase()) {
      console.log('Mismatch detected, updating distributor...');

      // Update distributor
      const tx = await disputer.connect(deployer).setDistributor(distributorAddress as string);
      await tx.wait();

      console.log('Successfully updated distributor');
    } else {
      console.log('Distributor addresses match');
    }
  } catch (error) {
    console.error(`Error on ${network.name}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });