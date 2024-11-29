import { execSync } from 'child_process';
import hre from 'hardhat';

async function main() {
  const networks = Object.keys(hre.config.networks);
  const chainsToSkip = ['hardhat', 'localhost', 'celo', 'astarzkevm', 'astar', 'aurora', 'filecoin', 'avalanche'];

  for (const network of networks) {
    // Skip networks that don't have Merkl deployed
    if (chainsToSkip.includes(network)) continue;

    console.log(`Running setDisputerOwner on ${network}...`);
    try {
      execSync(`npx hardhat run scripts/setDisputerOwner.ts --network ${network}`, { stdio: 'inherit' });
    } catch (error) {
      console.error(`Failed to run setDisputerOwner on ${network}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });