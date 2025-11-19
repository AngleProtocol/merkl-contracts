#!/bin/bash

# Script to generate a summary CSV/Markdown file from all deployment JSONs
# This makes it easy to create Gnosis Safe transactions

set -e

DEPLOYMENTS_DIR="deployments"
OUTPUT_CSV="deployments/upgrade-summary.csv"
OUTPUT_MD="deployments/upgrade-summary.md"

echo "Generating upgrade summary..."

# Create CSV header
echo "Chain,Chain ID,DistributionCreator Implementation,Distributor Implementation,Deployer,Timestamp" > "$OUTPUT_CSV"

# Create Markdown header
cat > "$OUTPUT_MD" << 'EOF'
# Upgrade Implementation Addresses

This file contains all deployed implementation addresses for upgrading DistributionCreator and Distributor contracts.

## Summary Table

| Chain | Chain ID | DistributionCreator Impl | Distributor Impl | Deployer | Timestamp |
|-------|----------|--------------------------|------------------|----------|-----------|
EOF

# Process each JSON file
for json_file in "$DEPLOYMENTS_DIR"/*-upgrade-implementations.json; do
    if [ -f "$json_file" ]; then
        # Extract data using jq
        if command -v jq &> /dev/null; then
            CHAIN=$(jq -r '.chainName' "$json_file")
            CHAIN_ID=$(jq -r '.chainId' "$json_file")
            DC_IMPL=$(jq -r '.distributionCreatorImplementation' "$json_file")
            DIST_IMPL=$(jq -r '.distributorImplementation' "$json_file")
            DEPLOYER=$(jq -r '.deployer' "$json_file")
            TIMESTAMP=$(jq -r '.timestamp' "$json_file")
            
            # Add to CSV
            echo "$CHAIN,$CHAIN_ID,$DC_IMPL,$DIST_IMPL,$DEPLOYER,$TIMESTAMP" >> "$OUTPUT_CSV"
            
            # Add to Markdown
            echo "| $CHAIN | $CHAIN_ID | \`$DC_IMPL\` | \`$DIST_IMPL\` | \`$DEPLOYER\` | $TIMESTAMP |" >> "$OUTPUT_MD"
        else
            echo "Warning: jq not installed, skipping $json_file"
        fi
    fi
done

# Add Gnosis Safe transaction template to Markdown
cat >> "$OUTPUT_MD" << 'EOF'

## Gnosis Safe Transaction Template

For each chain, create a transaction with the following details:

### UUPS Upgrade Transaction

**To**: `<Proxy Address>` (DistributionCreator or Distributor proxy)
**Value**: 0
**Data**: 
```
Function: upgradeTo(address newImplementation)
newImplementation: <Implementation Address from table above>
```

### Verification Steps

1. ✅ Verify implementation address matches table above
2. ✅ Verify proxy address is correct for the chain
3. ✅ Verify transaction data is correct
4. ✅ Simulate transaction before executing
5. ✅ Have multiple signers review

### Example Transaction (Arbitrum)

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

## Notes

- Always upgrade DistributionCreator first, then Distributor
- Test on a testnet proxy first if possible
- Monitor contract behavior after upgrade
- Keep these addresses for future reference

EOF

echo "✅ Summary generated:"
echo "   CSV: $OUTPUT_CSV"
echo "   Markdown: $OUTPUT_MD"
echo ""
echo "You can now use these files to create Gnosis Safe upgrade transactions."
