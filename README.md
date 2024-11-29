# <img src="logo.svg" alt="Merkl Contracts" height="40px"> Merkl Contracts

[![CI](https://github.com/AngleProtocol/merkl-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/AngleProtocol/merkl-contracts/actions)
[![Coverage](https://codecov.io/gh/AngleProtocol/merkl-contracts/branch/main/graph/badge.svg)](https://codecov.io/gh/AngleProtocol/merkl-contracts)

This repository contains the smart contracts of the Merkl product developed by Angle.

It basically contains two contracts:

- `DistributionCreator`: to which DAOs and individuals can deposit their rewards to incentivize a pool
- `Distributor`: the contract where users can claim their rewards

You can learn more about the Merkl system in the [documentation](https://docs.merkl.xyz/).

## Setup

### Install packages

You can install all dependencies by running

```bash
yarn
forge i
```

### Create `.env` file

You can copy paste `.env.example` file into `.env` and fill with your keys/RPCs.

Warning: always keep your confidential information safe.

### Tests

```bash
# Whole test suite
forge test
```

### Deploying

#### Foundry

Run without broadcasting:

```bash
yarn foundry:script <path_to_script> --rpc-url <network>
```

Run with broadcasting:

```bash
yarn foundry:deploy <path_to_script> --rpc-url <network>
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

## Audits

The Merkl smart contracts have been audited by Code4rena, find the audit report [here](https://code4rena.com/reports/2023-06-angle).

## Media

Don't hesitate to reach out on [Twitter](https://twitter.com/AngleProtocol) 🐦
