## Blast Withdrawal Scripts

Foundry scripts to complete withdrawal transactions from Blast L2 to Ethereum L1.

### Overview

When bridging assets from Blast (L2) to Ethereum (L1), the withdrawal process has three steps:

1. **Initiate withdrawal** on Blast L2 ✅ (already completed)
2. **Prove withdrawal** on Ethereum L1 (`ProveWithdrawal.s.sol`)
3. **Finalize withdrawal** on Ethereum L1 (`FinalizeWithdrawal.s.sol`) - after ~7 day challenge period

### Prerequisites

- Foundry installed
- `jq` installed (`brew install jq` on macOS)
- **IMPORTANT**: A Blast L2 RPC provider that supports `eth_getProof` (public RPC doesn't support it)
  - Recommended: [Alchemy](https://www.alchemy.com/), [QuickNode](https://www.quicknode.com/)
- Environment variables configured:
  - `ETH_NODE_URI_81457` - Blast L2 RPC endpoint (must support `eth_getProof`)
  - `ETH_NODE_URI_1` - Ethereum L1 RPC endpoint
  - `DEPLOYER_PRIVATE_KEY` - Private key for broadcasting on L1

### Quick Start

#### Step 2: Prove Withdrawal

For the withdrawal transaction `0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1`:

```bash
# 1. Dry run first (recommended)
forge script scripts/blast/ProveWithdrawal.s.sol:ProveBlastWithdrawal \
  --sig "run(bytes32)" 0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1 \
  --rpc-url mainnet

# 2. Broadcast (actual transaction)
forge script scripts/blast/ProveWithdrawal.s.sol:ProveBlastWithdrawal \
  --sig "run(bytes32)" 0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1 \
  --rpc-url mainnet \
  --broadcast
```

#### Step 3: Finalize Withdrawal (after 7 days)

After the challenge period has passed:

```bash
# 1. Check if ready to finalize (dry run)
forge script scripts/blast/FinalizeWithdrawal.s.sol:FinalizeBlastWithdrawal \
  --sig "run(bytes32)" 0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1 \
  --rpc-url mainnet

# 2. Finalize (actual transaction, with 5 times gas estimate)
forge script scripts/blast/FinalizeWithdrawal.s.sol:FinalizeBlastWithdrawal \
  --sig "run(bytes32)" 0x93fbcc9e6eb094ce6c5637f28a0ad0fd11ca95f0e728f53f162462df0e62fbb1 \
  --rpc-url mainnet \
  --broadcast --gas-estimate-multiplier 500 
```

### How It Works

#### ProveWithdrawal.s.sol

1. **Fetches withdrawal data** from Blast L2 using `cast receipt`
2. **Checks if already proven** on the OptimismPortal contract
3. **Waits for L2 output** to be available on L1 (submitted hourly)
4. **Generates proofs** using `eth_getProof` via the helper bash script
5. **Submits proof** to OptimismPortal on Ethereum L1

#### FinalizeWithdrawal.s.sol

1. **Fetches withdrawal data** from Blast L2
2. **Checks if already finalized** on the OptimismPortal contract
3. **Verifies withdrawal is proven** and gets proof timestamp
4. **Checks challenge period** has passed (7 days)
5. **Finalizes withdrawal** on OptimismPortal, releasing funds on L1

### Contract Addresses

- **OptimismPortal**: [`0x0Ec68c5B10F21EFFb74f2A5C61DFe6b08C0Db6Cb`](https://etherscan.io/address/0x0Ec68c5B10F21EFFb74f2A5C61DFe6b08C0Db6Cb)
- **L2OutputOracle**: [`0x826D1B0D4111Ad9146Eb8941D7Ca2B6a44215c76`](https://etherscan.io/address/0x826D1B0D4111Ad9146Eb8941D7Ca2B6a44215c76)

### Files

- **ProveWithdrawal.s.sol** - Step 2: Prove withdrawal on L1
- **FinalizeWithdrawal.s.sol** - Step 3: Finalize withdrawal on L1 (after 7 days)
- **getWithdrawalProof.sh** - Helper script to fetch storage proofs from Blast L2
- **README.md** - This file

### Troubleshooting

#### "L2 output not yet available on L1"

L2 state outputs are submitted to L1 approximately every hour. Wait and retry.

#### "Withdrawal already proven"

The withdrawal has been proven. Check if the challenge period has passed and proceed to step 3 (finalize withdrawal).

#### "Challenge period has not passed yet"

You must wait 7 days from the proof timestamp before finalizing. The script will show you the exact time remaining.

#### "Withdrawal not proven"

You must run `ProveWithdrawal.s.sol` first before you can finalize.

#### Permission denied on getWithdrawalProof.sh

```bash
chmod +x scripts/blast/getWithdrawalProof.sh
```

#### RPC doesn't support eth_getProof

The public Blast RPC (`https://rpc.blast.io`) does NOT support `eth_getProof`. You must use a paid provider:

- Alchemy: `https://blast-mainnet.g.alchemy.com/v2/YOUR_API_KEY`
- QuickNode: `https://YOUR_ENDPOINT.blast.quiknode.pro/YOUR_API_KEY/`

### Next Steps

After successfully proving the withdrawal:

1. **Wait 7 days** for the challenge period
2. **Run FinalizeWithdrawal.s.sol** to complete the withdrawal and receive funds on L1

You can check the status at any time by running either script in dry-run mode (without `--broadcast`).

### Links

- [Blast Docs](https://docs.blast.io/)
- [Optimism Bridge Spec](https://specs.optimism.io/protocol/bridges.html)
- [OptimismPortal on Etherscan](https://etherscan.io/address/0x0Ec68c5B10F21EFFb74f2A5C61DFe6b08C0Db6Cb#writeProxyContract)
