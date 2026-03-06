#!/bin/bash

# Script to fetch withdrawal proof data from Blast L2
# Usage: ./getWithdrawalProof.sh <storage_slot> <block_number> [rpc_url]

set -e  # Exit on error

SLOT=$1
BLOCK=$2
L2_MESSAGE_PASSER="0x4200000000000000000000000000000000000016"

# Use provided RPC URL or try environment variable
if [ -n "$3" ]; then
    RPC_URL=$3
elif [ -n "$ETH_NODE_URI_81457" ]; then
    RPC_URL=$ETH_NODE_URI_81457
else
    # Default to public Blast RPC
    RPC_URL="https://rpc.blast.io"
fi

# Convert block number to hex
BLOCK_HEX=$(printf "0x%x" "$BLOCK")

# Get storage proof using direct RPC call (cast proof has issues with Blast's response format)
PROOF_DATA=$(cast rpc eth_getProof "$L2_MESSAGE_PASSER" "[\"$SLOT\"]" "$BLOCK_HEX" --rpc-url "$RPC_URL" 2>&1)

if [ $? -ne 0 ]; then
    echo "Error fetching proof: $PROOF_DATA" >&2
    exit 1
fi

# Get block data
BLOCK_DATA=$(cast block "$BLOCK_HEX" --json --rpc-url "$RPC_URL" 2>&1)

if [ $? -ne 0 ]; then
    echo "Error fetching block data: $BLOCK_DATA" >&2
    exit 1
fi

# Parse the proof data using jq
STORAGE_HASH=$(echo "$PROOF_DATA" | jq -r '.storageHash')
# Get the first storage proof entry
STORAGE_PROOF=$(echo "$PROOF_DATA" | jq -r '.storageProof[0].proof')

# Parse block data
BLOCK_HASH=$(echo "$BLOCK_DATA" | jq -r '.hash')
STATE_ROOT=$(echo "$BLOCK_DATA" | jq -r '.stateRoot')

# Combine into single JSON output
jq -n \
  --arg stateRoot "$STATE_ROOT" \
  --arg hash "$BLOCK_HASH" \
  --arg storageHash "$STORAGE_HASH" \
  --argjson proof "$STORAGE_PROOF" \
  '{stateRoot: $stateRoot, hash: $hash, storageHash: $storageHash, proof: $proof}'
