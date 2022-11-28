// import { ethers, upgrades } from 'hardhat';

// async function main() {
//   /** FILL PROXY ADDRESS AS AN ARG */
//   const proxyAddress = '';
//   const [deployer] = await ethers.getSigners();
//   console.log('Deploying contracts with the account:', deployer.address);
//   const BaseFactoryV2 = await ethers.getContractFactory('BaseV2');
//   await upgrades.upgradeProxy(proxyAddress, BaseFactoryV2);
//   console.log('Contract updated');
// }

// // We recommend this pattern to be able to use async/await everywhere
// // and properly handle errors.
// main().catch(error => {
//   console.error(error);
//   process.exitCode = 1;
// });
