[![CI](https://github.com/AngleProtocol/merkl-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/AngleProtocol/merkl-contracts/actions)
[![Coverage](https://codecov.io/gh/AngleProtocol/merkl-contracts/branch/main/graph/badge.svg)](https://codecov.io/gh/AngleProtocol/merkl-contracts)

This repository contains the core smart contracts for the Merkl solution.

The system consists of two primary contracts:

- `DistributionCreator`: Allows DAOs and individuals to deposit rewards for incentivizing onchain actions
- `Distributor`: Enables users to claim their earned rewards

Learn more about Merkl in the [official documentation](https://docs.merkl.xyz).

## Setup

### Install packages

Install all dependencies by running:

```bash
bun i
```

### Create `.env` file

Copy the `.env.example` file to `.env` and populate it with your keys and RPC endpoints:

```bash
cp .env.example .env
```

**Warning:** Always keep your confidential information secure and never commit `.env` files to version control.

### Foundry Installation

Install Foundry using the official installer:

```bash
curl -L https://foundry.paradigm.xyz | bash

source /root/.zshrc
# or, if you're using bash: source /root/.bashrc

foundryup
```

## Tests

Run the complete test suite:

```bash
forge test
```

## Deploying

### Simulate deployment (dry run)

Run a script without broadcasting transactions to the network:

```bash
yarn foundry:script <path_to_script> --rpc-url <network>
```

### Deploy to network

Execute and broadcast transactions:

```bash
yarn foundry:deploy <path_to_script> --rpc-url <network>
```

## Scripts

Scripts can be executed with or without parameters:

1. **With parameters:** Pass values directly as command-line arguments
2. **Without parameters:** Modify default values within the script file before running

### Running Scripts

Execute scripts using the following pattern:

```bash
# With parameters - pass values as arguments
forge script scripts/MockToken.s.sol:Deploy --rpc-url <network> --sender <address> --broadcast -i 1 \
  --sig "run(string,string,uint8)" "MyToken" "MTK" 18

# Without parameters - modify default values in the script first
forge script scripts/MockToken.s.sol:Deploy --rpc-url <network> --sender <address> --broadcast -i 1

# Common options:
#   --broadcast         Broadcasts transactions to the network
#   --sender <address>  Address that will execute the script
#   -i 1                Opens an interactive prompt to securely enter the sender's private key
```

### Examples

#### Deploy a mock ERC20 token

```bash
forge script scripts/MockToken.s.sol:Deploy --rpc-url <network> --sender <address> --broadcast \
  --sig "run(string,string,uint8)" "MyToken" "MTK" 18
```

#### Mint tokens to an address

```bash
forge script scripts/MockToken.s.sol:Mint --rpc-url <network> --sender <address> --broadcast \
  --sig "run(address,address,uint256)" <token_address> <recipient> 1000000000000000000
```

#### Configure minimum reward token amount

```bash
forge script scripts/DistributionCreator.s.sol:SetRewardTokenMinAmounts --rpc-url <network> --sender <address> --broadcast \
  --sig "run(address,uint256)" <reward_token_address> <min_amount>
```

#### Set campaign fees

```bash
forge script scripts/DistributionCreator.s.sol:SetCampaignFees --rpc-url <network> --sender <address> --broadcast \
  --sig "run(uint32,uint256)" <campaign_type> <fees>
```

### Modifying Default Script Parameters

For scripts without parameters, modify the default values directly in the script file before execution:

```solidity
// In scripts/MockToken.s.sol:Deploy
function run() external broadcast {
  // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN PARAMETERS
  string memory name = 'My Token'; // <- Customize token name
  string memory symbol = 'MTK'; // <- Customize token symbol
  uint8 decimals = 18; // <- Customize decimal places
  _run(name, symbol, decimals);
}
```

## Audits

The Merkl smart contracts have been audited by Code4rena. View the [Code4rena audit report](https://code4rena.com/reports/2023-06-angle) for details.

## Access Control

![Access Control Schema](docs/access_control.svg)

## Media

Reach out to us on [Twitter](https://x.com/merkl_xyz) 🐦
