# <img src="logo.svg" alt="Merkl Contracts" height="40px"> Merkl Contracts

[![CI](https://github.com/AngleProtocol/merkl-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/AngleProtocol/merkl-contracts/actions)
[![Coverage](https://codecov.io/gh/AngleProtocol/merkl-contracts/branch/main/graph/badge.svg)](https://codecov.io/gh/AngleProtocol/merkl-contracts)

This repository contains the smart contracts of the Merkl product developed by Angle.

It basically contains two contracts:

- `DistributionCreator`: to which DAOs and individuals can deposit their rewards to incentivize a pool
- `Distributor`: the contract where users can claim their rewards

You can learn more about the Merkl system in the [documentation](https://docs.angle.money/side-products/merkl).

## Setup

### Install packages

You can install all dependencies by running

```bash
yarn
forge i
```

### Create `.env` file

In order to interact with non local networks, you must create an `.env` that has, for all supported networks (Ethereum, Polygon and Arbitrum):

- `MNEMONIC`
- `ETH_NODE_URI`
- `ETHERSCAN_API_KEY`

You can copy paste the `.env.example` file into `.env` and fill with your keys/RPCs.

Warning: always keep your confidential information safe.

### Tests

Contracts in this repo rely on Hardhat tests. You can run tests as follows:

```bash
# Whole test suite
yarn hardhat:test

# Only one file
yarn hardhat:test ./test/hardhat/distributor/distributor.test.ts
```

You can also check the coverage of the tests with:

```bash
yarn hardhat:coverage
```

### Deploying

```bash
yarn deploy mainnet
```

## Foundry Installation

```bash
curl -L https://foundry.paradigm.xyz | bash

source /root/.zshrc
# or, if you're under bash: source /root/.bashrc

foundryup
```

To install the standard library:

```bash
forge install foundry-rs/forge-std
```

To update libraries:

```bash
forge update
```

## Verifying

Blast: `yarn etherscan blast --api-url https://api.blastscan.io --solc-input --license BUSL-1.1`
Mantle: `yarn etherscan mantle --api-url https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan/api --solc-input --license BUSL-1.1`
Mode: `yarn etherscan mode --api-url https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan/api --solc-input --license BUSL-1.1`
ImmutableZKEVM: `yarn etherscan immutablezkevm --api-url https://explorer.immutable.com/api --solc-input --license BUSL-1.1`
Scroll:`yarn etherscan scroll --api-url https://api.scrollscan.com --solc-input --license BUSL-1.1`
Gnosis:`yarn etherscan gnosis --api-url https://api.gnosisscan.io --solc-input --license BUSL-1.1`
Linea:`yarn etherscan linea --api-url https://api.lineascan.build --solc-input --license BUSL-1.1`

## Audits

The Merkl smart contracts have been audited by Code4rena, find the audit report [here](https://code4rena.com/reports/2023-06-angle).

## Media

Don't hesitate to reach out on [Twitter](https://twitter.com/AngleProtocol) 🐦
