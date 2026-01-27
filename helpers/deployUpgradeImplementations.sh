#!/bin/bash

# Deployment script for upgrading DistributionCreator and Distributor implementations
# across all supported chains

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counter for results
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Create deployments directory if it doesn't exist
mkdir -p deployments

# Array of chains to deploy to (ordered by chainId to match foundry.toml)
CHAINS=(
    "mainnet"
    "optimism"
    "rootstock"
    "xdc"
    "bsc"
    "gnosis"
    "fuse"
    "unichain"
    "polygon"
    "monad"
    "sonic"
    "redbelly"
    "manta"
    "xlayer"
    "tac"
    "fraxtal"
    "zksync"
    "worldchain"
    "astar"
    "flow"
    "stable"
    "hyperevm"
    "lisk"
    "moonbeam"
    "sei"
    "soneium"
    "swell"
    "ronin"
    "citrea"
    "megaeth"
    "mantle"
    "saga"
    "nibiru"
    "base"
    "plasma"
    "immutable"
    "0g"
    "corn"
    "mezo"
    "apechain"
    "mode"
    "arbitrum"
    "celo"
    "etherlink"
    "hemi"
    "avalanche"
    "zircuit"
    "ink"
    "linea"
    "bob"
    "berachain"
    "blast"
    "plume"
    "taiko"
    "scroll"
    "katana"
    "skale"
    "ethereal"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Merkl Upgrade Implementations Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Deploying to ${#CHAINS[@]} chains..."
echo ""

# Create summary file
SUMMARY_FILE="deployments/deployment-summary-$(date +%Y%m%d-%H%M%S).txt"
echo "Deployment Summary - $(date)" > "$SUMMARY_FILE"
echo "===========================================" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Deploy to each chain
for CHAIN in "${CHAINS[@]}"; do
    echo -e "${YELLOW}------------------------------------------${NC}"
    echo -e "${YELLOW}Deploying to: $CHAIN${NC}"
    echo -e "${YELLOW}------------------------------------------${NC}"
    
    # Check if deployment already exists
    DEPLOYMENT_FILE="deployments/${CHAIN}-upgrade-implementations.json"
    if [ -f "$DEPLOYMENT_FILE" ]; then
        echo -e "${BLUE}ℹ Skipping $CHAIN: Deployment already exists${NC}"
        echo "⏭ SKIPPED: $CHAIN - Already deployed (JSON exists)" >> "$SUMMARY_FILE"
        ((SKIPPED_COUNT++))
        echo ""
        continue
    fi
    
    # Check if RPC URL is configured
    RPC_VAR="${CHAIN^^}_NODE_URI"
    if [ -z "${!RPC_VAR}" ]; then
        echo -e "${YELLOW}⚠ Skipping $CHAIN: RPC URL not configured${NC}"
        echo "❌ SKIPPED: $CHAIN - RPC URL not configured" >> "$SUMMARY_FILE"
        ((SKIPPED_COUNT++))
        echo ""
        continue
    fi
    
    # Try to deploy
    if forge script scripts/deployUpgradeImplementationsSingle.s.sol \
        --rpc-url "$CHAIN" \
        --broadcast \
        --verify \
        --skip-simulation \
        --slow \
        2>&1 | tee "deployments/${CHAIN}-deployment.log"; then
        
        echo -e "${GREEN}✅ Successfully deployed to $CHAIN${NC}"
        echo "✅ SUCCESS: $CHAIN" >> "$SUMMARY_FILE"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}❌ Failed to deploy to $CHAIN${NC}"
        echo "❌ FAILED: $CHAIN" >> "$SUMMARY_FILE"
        ((FAILED_COUNT++))
    fi
    
    echo ""
    
    # Small delay to avoid rate limiting
    sleep 2
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Successful: $SUCCESS_COUNT${NC}"
echo -e "${RED}Failed: $FAILED_COUNT${NC}"
echo -e "${YELLOW}Skipped: $SKIPPED_COUNT${NC}"
echo ""
echo "Summary saved to: $SUMMARY_FILE"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Review deployment logs in ./deployments/"
echo "2. Check individual chain JSON files for implementation addresses"
echo "3. Create Gnosis Safe transactions using the implementation addresses"
echo "4. For failed deployments, check logs and retry manually if needed"
echo ""
