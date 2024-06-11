import { deployments, ethers } from 'hardhat';

import { DistributionCreator, DistributionCreator__factory, Distributor, Distributor__factory } from '../typechain';
import { parseEther, parseUnits, getAddress } from 'ethers/lib/utils';
import { registry } from '@angleprotocol/sdk';
import { BigNumber } from 'ethers';
import { BASE_PARAMS } from '../test/hardhat/utils/helpers';
import fs from 'fs';

async function main() {
  let distributionCreator: DistributionCreator;
  let distributor: Distributor;
  const { deployer } = await ethers.getNamedSigners();
  const chainId = (await deployer.provider?.getNetwork())?.chainId;
  console.log('chainId', chainId);
  const distributionCreatorAddress = registry(chainId as unknown as number)?.Merkl?.DistributionCreator; // (await deployments.get('DistributionCreator')).address;
  const distributorAddress = registry(chainId as unknown as number)?.Merkl?.Distributor; // (await deployments.get('DistributionCreator')).address;

  if (!distributionCreatorAddress) {
    throw new Error('Distribution Creator address not found');
  }
  if (!distributorAddress) {
    throw new Error('Distributor address not found');
  }

  distributionCreator = new ethers.Contract(
    distributionCreatorAddress,
    DistributionCreator__factory.createInterface(),
    deployer,
  ) as DistributionCreator;

  distributor = new ethers.Contract(
    distributorAddress,
    Distributor__factory.createInterface(),
    deployer,
  ) as Distributor;

  const disputeToken = await distributor.disputeToken()
  const disputer = await distributor.disputer()

  fs.writeFileSync(
    `${(await deployer?.provider?.getNetwork())?.name}_dispute.json`,
    `{"version":"1.0","chainId":"${chainId}","createdAt":1693483753967,"meta":{"name":"Transactions Batch","description":"","txBuilderVersion":"1.16.2","createdFromSafeAddress":"0xe4BB74804edf5280c9203f034036f7CB15196078","createdFromOwnerAddress":"","checksum":"0xb9377def98483d3d19bd3e1f34d7e2ca1055a92ed09d35bd90bb4892f60c2d2e"},"transactions":[{"to":"0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae","value":"0","data":null,"contractMethod":{"inputs":[{"internalType":"bool","name":"valid","type":"bool"}],"name":"resolveDispute","payable":false},"contractInputsValues":{"valid":"false"}},{"to":"${disputeToken}","value":"0","data":null,"contractMethod":{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"transfer","payable":false},"contractInputsValues":{"to":"${disputer}","amount":"100000000000000000000"}}]}`,
  );
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
