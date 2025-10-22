# Upgrade Implementation Deployment Guide

This guide explains how to deploy new implementations of `DistributionCreator` and `Distributor` contracts across all supported chains for upgrading existing proxies.

## 🚀 Quick Start (TL;DR)

Deploy new implementations across all chains and generate summary for Gnosis Safe transactions:

```bash
# 1. Deploy to all chains
./helpers/deployUpgradeImplementations.sh

# 2. Generate summary report
./helpers/generateUpgradeSummary.sh

# 3. Check results
cat deployments/upgrade-summary.md
```

### Single Chain Deployment

```bash
forge script scripts/deployUpgradeImplementationsSingle.s.sol \
    --rpc-url <chain> \
    --broadcast \
    --verify
```

### Common Chains Examples

```bash
# Arbitrum
forge script scripts/deployUpgradeImplementationsSingle.s.sol --rpc-url arbitrum --broadcast --verify

# Base
forge script scripts/deployUpgradeImplementationsSingle.s.sol --rpc-url base --broadcast --verify

# Polygon
forge script scripts/deployUpgradeImplementationsSingle.s.sol --rpc-url polygon --broadcast --verify

# Optimism
forge script scripts/deployUpgradeImplementationsSingle.s.sol --rpc-url optimism --broadcast --verify

# Mainnet
forge script scripts/deployUpgradeImplementationsSingle.s.sol --rpc-url mainnet --broadcast --verify
```

---

## 📋 Overview

The deployment process consists of:

1. Deploying new implementation contracts on each chain
2. Verifying the contracts on block explorers
3. Saving deployment addresses to JSON files per chain
4. Using these addresses to create Gnosis Safe upgrade transactions

## 📁 Files

- `scripts/deployUpgradeImplementationsSingle.s.sol` - Foundry script for single chain deployment
- `helpers/deployUpgradeImplementations.sh` - Bash script for automated multi-chain deployment
- `helpers/generateUpgradeSummary.sh` - Script to generate summary reports from deployments
- `deployments/*.json` - Generated JSON files with deployment addresses per chain
- `deployments/upgrade-summary.csv` - CSV summary of all deployments
- `deployments/upgrade-summary.md` - Markdown summary with Gnosis Safe templates

## ⚙️ Prerequisites

1. **Environment Variables**: Ensure your `.env` file contains:

   ```bash
   DEPLOYER_PRIVATE_KEY=your_private_key_here

   # RPC URLs for each chain
   MAINNET_NODE_URI=https://...
   POLYGON_NODE_URI=https://...
   # ... and so on for all chains

   # Etherscan API keys for verification
   MAINNET_ETHERSCAN_API_KEY=...
   POLYGON_ETHERSCAN_API_KEY=...
   # ... and so on
   ```

2. **Dependencies**: Make sure you have:
   - Foundry installed and updated (`foundryup`)
   - Sufficient balance on deployer address for gas on each chain

## 🎯 Deployment Methods

### Option 1: Deploy to All Chains (Automated)

Run the bash script to deploy across all chains:

```bash
./helpers/deployUpgradeImplementations.sh
```

This will:

- Iterate through all supported chains
- Skip chains without configured RPC URLs
- Handle failures gracefully and continue
- Generate logs for each chain in `deployments/`
- Create a summary file with results

### Option 2: Deploy to Single Chain

Deploy to a specific chain:

```bash
forge script scripts/deployUpgradeImplementationsSingle.s.sol \
    --rpc-url <chain_name> \
    --broadcast \
    --verify
```

Examples:

```bash
# Deploy to Arbitrum
forge script scripts/deployUpgradeImplementationsSingle.s.sol \
    --rpc-url arbitrum \
    --broadcast \
    --verify

# Deploy to Base
forge script scripts/deployUpgradeImplementationsSingle.s.sol \
    --rpc-url base \
    --broadcast \
    --verify
```

### Option 3: Deploy Without Verification

If verification fails or you want to verify manually later:

```bash
forge script scripts/deployUpgradeImplementationsSingle.s.sol \
    --rpc-url <chain_name> \
    --broadcast
```

## 📊 Output Files

After deployment, you'll find the following files in the `deployments/` directory:

### Per-Chain JSON Files

Example: `deployments/arbitrum-upgrade-implementations.json`

```json
{
  "chainId": 42161,
  "chainName": "arbitrum",
  "distributionCreatorImplementation": "0x...",
  "distributorImplementation": "0x...",
  "timestamp": 1234567890,
  "deployer": "0x..."
}
```

### Summary Files

- `deployments/<chain>-upgrade-implementations.json` - Individual deployment data
- `deployments/<chain>-deployment.log` - Deployment logs
- `deployments/upgrade-summary.csv` - CSV summary of all deployments
- `deployments/upgrade-summary.md` - Markdown summary with Gnosis Safe templates
- `deployments/deployment-summary-<timestamp>.txt` - Overall deployment status

## ✅ Manual Verification

If automatic verification fails, verify manually:

```bash
# Verify DistributionCreator
forge verify-contract \
    <implementation_address> \
    contracts/DistributionCreator.sol:DistributionCreator \
    --chain <chain_name> \
    --watch

# Verify Distributor
forge verify-contract \
    <implementation_address> \
    contracts/Distributor.sol:Distributor \
    --chain <chain_name> \
    --watch
```

## 🔐 Creating Gnosis Safe Upgrade Transactions

After deploying implementations, create upgrade transactions:

1. **Review the summary**: Check `deployments/upgrade-summary.md`
2. **For each chain**, navigate to the Gnosis Safe UI
3. **Create a new transaction** to the proxy contract
4. **Call `upgradeTo(address)`** or `upgradeToAndCall(address,bytes)` function
5. **Use the implementation address** from the JSON file
6. **Get multiple signers to review** the transaction
7. **Execute** the upgrade transaction
8. **Monitor** contract behavior after upgrade

### Example Upgrade Transaction Data

For a UUPS proxy:

```solidity
// Function: upgradeTo(address)
// Implementation: 0x... (from JSON file)
```

### Example Transactions

```
To: 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd (DistributionCreator Proxy)
Value: 0 ETH
Function: upgradeTo(address)
Parameter: 0x<DistributionCreator Implementation Address>
```

```
To: 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae (Distributor Proxy)
Value: 0 ETH
Function: upgradeTo(address)
Parameter: 0x<Distributor Implementation Address>
```

## 🔧 Troubleshooting

### RPC Errors

- Check RPC URL is correct and accessible
- Try with a different RPC provider
- Some chains may have rate limits

### Verification Failures

- Verify manually using the commands above
- Check Etherscan API key is correct
- Some explorers may have delays - try again later

### Gas Issues

- Ensure deployer has sufficient native token balance
- Adjust gas price if needed: `--with-gas-price <amount>`
- Use `--legacy` flag for chains without EIP-1559

### Chain-Specific Issues

**ZKSync**: Requires special compilation

```bash
forge script --zksync --system-mode=true ...
```

**Skale**: May need custom gas settings

```bash
forge script --legacy ...
```

**Chain not supported**: Deploy manually and add to JSON format

## ✓ Pre-Deployment Checklist

Before upgrading proxies, verify:

- [ ] All implementations deployed successfully
- [ ] All contracts verified on block explorers
- [ ] JSON files saved with correct addresses
- [ ] Deployment address matches expected deployer
- [ ] Storage layout compatible with previous version
- [ ] No constructor initializes state (use `initialize()` instead)
- [ ] Tested on testnet first
- [ ] Multiple signers reviewed transactions
- [ ] Monitoring plan in place

## ⚠️ Safety Notes

**IMPORTANT**:

- Test upgrades on testnets first
- Verify storage layout compatibility
- Check for breaking changes in new implementation
- Have multiple signers review upgrade transactions
- Monitor contract behavior after upgrade
- Always upgrade DistributionCreator first, then Distributor
- Keep backup of all implementation addresses

## 🌐 Chain-Specific Notes

### Mainnet

- High gas costs - deploy during low activity periods
- Use gas estimation tools

### L2s (Arbitrum, Optimism, Base, etc.)

- Lower gas costs
- Faster confirmation times

### Alternative L1s/L2s

- May have different gas mechanics
- Check block explorer supports verification
- Some may require manual verification

## 📝 Post-Deployment Tasks

1. Save all JSON files to secure location
2. Document implementation addresses in internal docs
3. Create upgrade proposals for each chain
4. Schedule upgrade transactions
5. Monitor contracts after upgrades
6. Update documentation with new version
7. Generate summary report: `./helpers/generateUpgradeSummary.sh`

## 📚 Support

For issues or questions:

- Check Foundry documentation: <https://book.getfoundry.sh/>
- Review deployment logs in `deployments/` folder
- Contact team for chain-specific issues
