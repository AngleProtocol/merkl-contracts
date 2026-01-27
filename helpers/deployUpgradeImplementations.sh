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

# Load environment variables from .env file
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Counter for results
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Create deployments directory if it doesn't exist
mkdir -p deployments

# Function to get chainId from chain name
get_chain_id() {
    case "$1" in
        "mainnet") echo "1" ;;
        "optimism") echo "10" ;;
        "rootstock") echo "30" ;;
        "xdc") echo "50" ;;
        "bsc") echo "56" ;;
        "gnosis") echo "100" ;;
        "fuse") echo "122" ;;
        "unichain") echo "130" ;;
        "polygon") echo "137" ;;
        "monad") echo "143" ;;
        "sonic") echo "146" ;;
        "redbelly") echo "151" ;;
        "manta") echo "169" ;;
        "xlayer") echo "196" ;;
        "tac") echo "239" ;;
        "fraxtal") echo "252" ;;
        "zksync") echo "324" ;;
        "worldchain") echo "480" ;;
        "astar") echo "592" ;;
        "flow") echo "747" ;;
        "stable") echo "988" ;;
        "hyperevm") echo "999" ;;
        "lisk") echo "1135" ;;
        "moonbeam") echo "1284" ;;
        "sei") echo "1329" ;;
        "soneium") echo "1868" ;;
        "swell") echo "1923" ;;
        "ronin") echo "2020" ;;
        "citrea") echo "4114" ;;
        "megaeth") echo "4326" ;;
        "mantle") echo "5000" ;;
        "saga") echo "5464" ;;
        "nibiru") echo "6900" ;;
        "base") echo "8453" ;;
        "plasma") echo "9745" ;;
        "immutable") echo "13371" ;;
        "0g") echo "16661" ;;
        "corn") echo "21000000" ;;
        "mezo") echo "31612" ;;
        "apechain") echo "33139" ;;
        "mode") echo "34443" ;;
        "arbitrum") echo "42161" ;;
        "celo") echo "42220" ;;
        "etherlink") echo "42793" ;;
        "hemi") echo "43111" ;;
        "avalanche") echo "43114" ;;
        "zircuit") echo "48900" ;;
        "ink") echo "57073" ;;
        "linea") echo "59144" ;;
        "bob") echo "60808" ;;
        "berachain") echo "80094" ;;
        "blast") echo "81457" ;;
        "plume") echo "98866" ;;
        "taiko") echo "167000" ;;
        "scroll") echo "534352" ;;
        "katana") echo "747474" ;;
        "skale") echo "2046399126" ;;
        "ethereal") echo "5064014" ;;
        *) echo "" ;;
    esac
}

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
    
    # Get chainId and check if RPC URL is configured
    CHAIN_ID=$(get_chain_id "$CHAIN")
    RPC_VAR="ETH_NODE_URI_${CHAIN_ID}"
    if [ -z "${!RPC_VAR}" ]; then
        echo -e "${YELLOW}⚠ Skipping $CHAIN: RPC URL not configured (${RPC_VAR})${NC}"
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
        --legacy \
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
