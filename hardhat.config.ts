/// ENVVAR
// - ENABLE_GAS_REPORT
// - CI
// - RUNS
import 'dotenv/config';
import 'hardhat-contract-sizer';
import 'hardhat-spdx-license-identifier';
import 'hardhat-deploy';
import 'hardhat-abi-exporter';
import '@nomicfoundation/hardhat-chai-matchers'; /** NEW FEATURE - https://hardhat.org/hardhat-chai-matchers/docs/reference#.revertedwithcustomerror */
import '@nomicfoundation/hardhat-toolbox'; /** NEW FEATURE */
import '@openzeppelin/hardhat-upgrades';
import '@nomiclabs/hardhat-truffle5';
import '@nomiclabs/hardhat-solhint';
import '@tenderly/hardhat-tenderly';
import '@typechain/hardhat';

import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from 'hardhat/builtin-tasks/task-names';
import { HardhatUserConfig, subtask } from 'hardhat/config';
import { HardhatNetworkAccountsUserConfig } from 'hardhat/types';
import yargs from 'yargs';

import { accounts, etherscanKey, getPkey, nodeUrl } from './utils/network';

// Otherwise, ".sol" files from "test" are picked up during compilation and throw an error
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
  const paths = await runSuper();
  return paths.filter((p: string) => !p.includes('/test/foundry/'));
});

const accountsPkey = [getPkey()];
const accountsMerklDeployer: HardhatNetworkAccountsUserConfig = accounts('merkl_deployer');

const argv = yargs
  .env('')
  .boolean('enableGasReport')
  .boolean('ci')
  .number('runs')
  .boolean('fork')
  .boolean('disableAutoMining')
  .parseSync();

if (argv.enableGasReport) {
  import('hardhat-gas-reporter'); // eslint-disable-line
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 100000,
          },
          viaIR: false,
        },
      },
    ],
    overrides: {
      'contracts/DistributionCreator.sol': {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
          viaIR: false,
        },
      },
      'contracts/mock/DistributionCreatorUpdatable.sol': {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
          viaIR: false,
        },
      },
      'contracts/deprecated/OldDistributionCreator.sol': {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
          viaIR: false,
        },
      },
    },
  },
  defaultNetwork: 'hardhat',
  // For the lists of Chain ID: https://chainlist.org
  networks: {
    hardhat: {
      live: false,
      blockGasLimit: 125e5,
      initialBaseFeePerGas: 0,
      hardfork: 'london',
      forking: {
        enabled: argv.fork || false,
        // Mainnet
        /*
        url: nodeUrl('fork'),
        blockNumber: 19127150,
        */
        // Polygon
        /*
        url: nodeUrl('forkpolygon'),
        blockNumber: 39517477,
        */
        // Optimism
        /*
        url: nodeUrl('optimism'),
        blockNumber: 17614765,
        */
        // Arbitrum
        /*
        url: nodeUrl('arbitrum'),
        blockNumber: 19356874,
        */
        /*
        url: nodeUrl('arbitrum'),
        blockNumber: 19356874,
        */
        /*
        url: nodeUrl('polygonzkevm'),
        blockNumber: 3214816,
        */
        /*
        url: nodeUrl('coredao'),
        */
        /*
        url: nodeUrl('gnosis'),
        blockNumber: 14188687,
        */
        /*
        url: nodeUrl('immutable'),
        blockNumber: 3160413,
        */
        /*
        url: nodeUrl('manta'),
        blockNumber: 1479731,
        */
        /*
        url: nodeUrl('scroll'),
        blockNumber: 3670869,
        */
        url: nodeUrl('blast'),
        blockNumber: 421659,
      },
      mining: argv.disableAutoMining
        ? {
            auto: false,
            interval: 1000,
          }
        : { auto: true },
      chainId: 100,
    },
    polygon: {
      live: true,
      url: nodeUrl('polygon'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 3,
      chainId: 137,
      gasPrice: 'auto',
      verify: {
        etherscan: {
          apiKey: etherscanKey('polygon'),
        },
      },
    },
    fantom: {
      live: true,
      url: nodeUrl('fantom'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 250,
      verify: {
        etherscan: {
          apiKey: etherscanKey('fantom'),
        },
      },
    },
    mainnet: {
      live: true,
      url: nodeUrl('mainnet'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 1,
      verify: {
        etherscan: {
          apiKey: etherscanKey('mainnet'),
        },
      },
    },
    optimism: {
      live: true,
      url: nodeUrl('optimism'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 10,
      verify: {
        etherscan: {
          apiKey: etherscanKey('optimism'),
        },
      },
    },
    arbitrum: {
      live: true,
      url: nodeUrl('arbitrum'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 42161,
      verify: {
        etherscan: {
          apiKey: etherscanKey('arbitrum'),
        },
      },
    },
    avalanche: {
      live: true,
      url: nodeUrl('avalanche'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 43114,
      verify: {
        etherscan: {
          apiKey: etherscanKey('avalanche'),
        },
      },
    },
    aurora: {
      live: true,
      url: nodeUrl('aurora'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 1313161554,
      verify: {
        etherscan: {
          apiKey: etherscanKey('aurora'),
        },
      },
    },
    bsc: {
      live: true,
      url: nodeUrl('bsc'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 56,
      verify: {
        etherscan: {
          apiKey: etherscanKey('bsc'),
        },
      },
    },
    gnosis: {
      live: true,
      url: nodeUrl('gnosis'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 3,
      chainId: 100,
      initialBaseFeePerGas: 2000000000,
      verify: {
        etherscan: {
          apiKey: etherscanKey('gnosis'),
        },
      },
    },
    polygonzkevm: {
      live: true,
      url: nodeUrl('polygonzkevm'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 1101,
      verify: {
        etherscan: {
          apiKey: etherscanKey('polygonzkevm'),
        },
      },
    },
    base: {
      live: true,
      url: nodeUrl('base'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 8453,
      verify: {
        etherscan: {
          apiKey: etherscanKey('base'),
        },
      },
    },
    linea: {
      live: true,
      url: nodeUrl('linea'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 59144,
      verify: {
        etherscan: {
          apiKey: etherscanKey('linea'),
        },
      },
    },
    zksync: {
      live: true,
      url: nodeUrl('zksync'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 324,
      verify: {
        etherscan: {
          apiKey: etherscanKey('zksync'),
        },
      },
    },
    mantle: {
      live: true,
      url: nodeUrl('mantle'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 5000,
      verify: {
        etherscan: {
          apiKey: etherscanKey('mantle'),
        },
      },
    },
    filecoin: {
      live: true,
      url: nodeUrl('filecoin'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 314,
      verify: {
        etherscan: {
          apiKey: etherscanKey('filecoin'),
        },
      },
    },
    blast: {
      live: true,
      url: nodeUrl('blast'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 81457,
      verify: {
        etherscan: {
          apiKey: etherscanKey('blast'),
        },
      },
    },
    thundercore: {
      live: true,
      url: nodeUrl('thundercore'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 108,
      verify: {
        etherscan: {
          apiKey: etherscanKey('thundercore'),
        },
      },
    },
    coredao: {
      live: true,
      url: nodeUrl('coredao'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 1116,
      verify: {
        etherscan: {
          apiKey: etherscanKey('coredao'),
        },
      },
    },
    immutablezkevm: {
      live: true,
      url: nodeUrl('immutablezkevm'),
      accounts: [getPkey()],
      gas: 'auto',
      gasMultiplier: 1.3,
      chainId: 13371,
      verify: {
        etherscan: {
          apiKey: etherscanKey('immutablezkevm'),
        },
      },
    },
    immutable: {
      live: true,
      url: nodeUrl('immutable'),
      accounts: accountsMerklDeployer,
      gas: 'auto',
      chainId: 13371,
      verify: {
        etherscan: {
          apiKey: etherscanKey('immutable'),
        },
      },
    },
    scroll: {
      live: true,
      url: nodeUrl('scroll'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 534352,
      verify: {
        etherscan: {
          apiKey: etherscanKey('scroll'),
        },
      },
    },
    manta: {
      live: true,
      url: nodeUrl('manta'),
      accounts: [getPkey()],
      gas: 'auto',
      chainId: 169,
      verify: {
        etherscan: {
          apiKey: etherscanKey('manta'),
        },
      },
    },
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: 'cache-hh',
  },
  namedAccounts: {
    deployer: 0,
    guardian: 1,
    governor: 2,
    proxyAdmin: 3,
    alice: 4,
    bob: 5,
    charlie: 6,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
  gasReporter: {
    currency: 'USD',
    outputFile: argv.ci ? 'gas-report.txt' : undefined,
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  abiExporter: {
    path: './export/abi',
    clear: true,
    flat: true,
    spacing: 2,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
};

export default config;
