import { UpgradeableContract, ValidationOptions } from '@openzeppelin/upgrades-core';
import { artifacts } from 'hardhat';

const upgradesOptions: ValidationOptions = {
  kind: 'transparent',
};

const testUpgradeability = async (name: string, file: string) => {
  const buildInfo = await artifacts.getBuildInfo(`${file}:${name}`);
  const baseContract = new UpgradeableContract(
    name,
    buildInfo?.input as any,
    buildInfo?.output as any,
    upgradesOptions,
  );
  console.log(name);
  console.log(baseContract.getErrorReport().explain());
  console.log('');
};

const testStorage = async (name: string, file: string, nameUpgrade: string, fileUpgrade: string) => {
  const buildInfo = await artifacts.getBuildInfo(`${file}:${name}`);
  const baseContract = new UpgradeableContract(
    name,
    buildInfo?.input as any,
    buildInfo?.output as any,
    upgradesOptions,
  );

  const upgradeBuildInfo = await artifacts.getBuildInfo(`${fileUpgrade}:${nameUpgrade}`);
  const upgradeContract = new UpgradeableContract(
    nameUpgrade,
    upgradeBuildInfo?.input as any,
    upgradeBuildInfo?.output as any,
  );
  console.log('Upgrade Testing');
  console.log(baseContract.getStorageUpgradeReport(upgradeContract).explain());
  console.log('');
};

async function main() {
  // Uncomment to check all valid build names
  // console.log((await artifacts.getAllFullyQualifiedNames()));

  testUpgradeability('MockAgEURUpgradeable', 'contracts/example/MockAgEURUpgradeable.sol');
  testStorage(
    'MockAgEURUpgradeable2',
    'contracts/example/MockAgEURUpgradeable2.sol',
    'MockAgEURUpgradeable',
    'contracts/example/MockAgEURUpgradeable.sol',
  );
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
