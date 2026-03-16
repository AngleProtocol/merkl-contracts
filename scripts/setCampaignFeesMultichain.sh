#!/bin/bash

CHAINS=(mainnet optimism rootstock bsc gnosis fuse unichain polygon monad sonic redbelly manta xlayer tac fraxtal zksync worldchain astar flow hyperevm stable lisk moonbeam sei soneium swell ronin citrea megaeth mantle saga nibiru base plasma immutable 0g corn mezo apechain mode arbitrum celo etherlink hemi avalanche zircuit ink linea bob berachain blast plume taiko scroll katana skale ethereal)

FAILED=()
SUCCESS=()

for chain in "${CHAINS[@]}"; do
  echo "=== $chain ==="
  if forge script scripts/setCampaignFeesMultichain.s.sol:SetCampaignFeesMultichain --rpc-url "$chain" --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast; then
    SUCCESS+=("$chain")
  else
    echo "FAILED: $chain"
    FAILED+=("$chain")
  fi
  echo ""
done

echo "=== SUMMARY ==="
echo "Success: ${#SUCCESS[@]}"
echo "Failed:  ${#FAILED[@]}"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "Failed chains:"
  for chain in "${FAILED[@]}"; do
    echo "  - $chain"
  done
fi
