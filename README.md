[![CI](https://github.com/AngleProtocol/merkl-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/AngleProtocol/merkl-contracts/actions)
[![Coverage](https://codecov.io/gh/AngleProtocol/merkl-contracts/branch/main/graph/badge.svg)](https://codecov.io/gh/AngleProtocol/merkl-contracts)

This repository contains the smart contracts of Merkl.

It basically contains two contracts:

- `DistributionCreator`: to which DAOs and individuals can deposit their rewards to incentivize onchain actions
- `Distributor`: the contract where users can claim their rewards

You can learn more about the Merkl system in the [documentation](https://docs.merkl.xyz).

## Setup

@@ -25,7 +25,7 @@ forge i

### Create `.env` file

In order to interact with non local networks, you must create an `.env` that has, for all supported networks:

- `MNEMONIC`
- `ETH_NODE_URI`
  @@ -84,18 +84,52 @@ forge update

## Verifying

Blast:

```
yarn etherscan blast --api-url https://api.blastscan.io --solc-input --license BUSL-1.1
```

Mantle:

```
yarn etherscan mantle --api-url https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan/api --solc-input --license BUSL-1.1
```

Mode:

```
yarn etherscan mode --api-url https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan/api --solc-input --license BUSL-1.1
```

ImmutableZKEVM:

```
yarn etherscan immutablezkevm --api-url https://explorer.immutable.com/api --solc-input --license BUSL-1.1
```

Scroll:

```
yarn etherscan scroll --api-url https://api.scrollscan.com --solc-input --license BUSL-1.1
```

Gnosis:

```
yarn etherscan gnosis --api-url https://api.gnosisscan.io --solc-input --license BUSL-1.1
```

Linea:

```
yarn etherscan linea --api-url https://api.lineascan.build --solc-input --license BUSL-1.1
```

## Audits

The Merkl smart contracts have been audited by Code4rena, find the audit report [here](https://code4rena.com/reports/2023-06-angle).

## Media

Don't hesitate to reach out on [Twitter](https://x.com/merkl_xyz)
