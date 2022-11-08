import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deploying contracts with the account:', deployer.address);
  const MockAgEURFactory = await ethers.getContractFactory('MockAgEUR', { signer: deployer });
  const token = await MockAgEURFactory.deploy();
  console.log('Contract deployed at address', token?.address);
  await token.deployed();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
