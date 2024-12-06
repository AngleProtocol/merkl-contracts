[![CI](https://github.com/AngleProtocol/merkl-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/AngleProtocol/merkl-contracts/actions)
[![Coverage](https://codecov.io/gh/AngleProtocol/merkl-contracts/branch/main/graph/badge.svg)](https://codecov.io/gh/AngleProtocol/merkl-contracts)

This repository contains the smart contracts of Merkl.

It basically contains two contracts:

- `DistributionCreator`: to which DAOs and individuals can deposit their rewards to incentivize onchain actions
- `Distributor`: the contract where users can claim their rewards

You can learn more about the Merkl system in the [documentation](https://docs.merkl.xyz).

## Setup

### Install packages

You can install all dependencies by running

```bash
bun i
```

### Create `.env` file

You can copy paste `.env.example` file into `.env` and fill with your keys/RPCs.

Warning: always keep your confidential information safe.

### Foundry Installation

```bash
curl -L https://foundry.paradigm.xyz | bash

source /root/.zshrc
# or, if you're under bash: source /root/.bashrc

foundryup
```

## Tests

```bash
# Whole test suite
forge test
```

## Deploying

Run without broadcasting:

```bash
yarn foundry:script <path_to_script> --rpc-url <network>
```

Run with broadcasting:

```bash
yarn foundry:deploy <path_to_script> --rpc-url <network>
```

## Scripts

Scripts can be executed in two ways:

1. With parameters: directly passing values as arguments
2. Without parameters: modifying the default values in the script

### Running Scripts

```bash
# With parameters
forge script scripts/MockToken.s.sol:Deploy --rpc-url <network> --sender <address> --broadcast -i 1 \
  --sig "run(string,string,uint8)" "MyToken" "MTK" 18

# Without parameters (modify default values in the script first)
forge script scripts/MockToken.s.sol:Deploy --rpc-url <network> --sender <address> --broadcast -i 1

# Common options:
#   --broadcast         Broadcasts the transactions to the network
#   --sender <address>  The address which will execute the script
#   -i 1                Open an interactive prompt to enter private key of the sender when broadcasting
```

### Examples

```bash
# Deploy a Mock Token
forge script scripts/MockToken.s.sol:Deploy --rpc-url <network> --sender <address> --broadcast \
  --sig "run(string,string,uint8)" "MyToken" "MTK" 18

# Mint tokens
forge script scripts/MockToken.s.sol:Mint --rpc-url <network> --sender <address> --broadcast \
  --sig "run(address,address,uint256)" <token_address> <recipient> 1000000000000000000

# Set minimum reward token amount
forge script scripts/DistributionCreator.s.sol:SetRewardTokenMinAmounts --rpc-url <network> --sender <address> --broadcast \
  --sig "run(address,uint256)" <reward_token_address> <min_amount>

# Set fees for campaign
forge script scripts/DistributionCreator.s.sol:SetCampaignFees --rpc-url <network> --sender <address> --broadcast \
  --sig "run(uint32,uint256)" <campaign_type> <fees>

# Toggle token whitelist status
forge script scripts/DistributionCreator.s.sol:ToggleTokenWhitelist --rpc-url <network> --sender <address> --broadcast \
  --sig "run(address)" <token_address>
```

For scripts without parameters, you can modify the default values directly in the script file:

```solidity
// In scripts/MockToken.s.sol:Deploy
function run() external broadcast {
  // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN PARAMETERS
  string memory name = 'My Token'; // <- modify this
  string memory symbol = 'MTK'; // <- modify this
  uint8 decimals = 18; // <- modify this
  _run(name, symbol, decimals);
}
```

## Audits

The Merkl smart contracts have been audited by Code4rena, find the audit report [here](https://code4rena.com/reports/2023-06-angle).

## Media

Don't hesitate to reach out on [Twitter](https://x.com/merkl_xyz)
