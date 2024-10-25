import { execSync } from 'child_process';
import hre from 'hardhat';

async function main() {
  const networks = Object.keys(hre.config.networks);
  const chainsToSkip = ['hardhat', 'localhost', 'celo'];
  // celo is skipped because CreateX is not deployed on it

  for (const network of networks) {
    // Skip default hardhat network and localhost
    if (chainsToSkip.includes(network)) continue;

    console.log(`Deploying Disputer to ${network}...`);
    try {
      execSync(`yarn hardhat:deploy-ignition ignition/modules/Disputer.ts --network ${network} --strategy create2`, { stdio: 'inherit' });
      console.log(`Successfully deployed Disputer to ${network}`);
    } catch (error) {
      console.error(`Failed to deploy Disputer to ${network}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });