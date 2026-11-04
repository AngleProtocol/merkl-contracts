# Elysium deployment and smoke test

Chain: `99901`. Native token: HYPE. The public RPC is not required for this procedure.

## Deployment record

`foundry.toml` provides the `elysium` RPC alias through `ETH_NODE_URI_99901` and the partner verification gateway through `ELYSIUM_ACCESS_CODE`.
Keep both values in the secret store; do not commit credentials.

`scripts/deployElysiumMultisig.s.sol` records the initial Safe v1.3.0 deployment through the existing factory.
The Safe is already deployed at `0x225D684C1a8f4d9c894d0E9e4B35755C62Cbc3d1` with six owners and threshold four.
Do not rerun deployment: the factory rejects a second deployment with the same owners and salt, and the script refuses to run
once the Merkl deployer nonce is no longer zero, so the Safe cannot consume the nonce reserved for deterministic Merkl addresses.
Its `verify(address)` entry point is read-only and checks the owners, threshold, modules, guard, singleton and fallback handler.
It does not check the Safe nonce, so it stays valid after the multisig executes transactions.

## Prerequisites for a real campaign

- Release Elysium `TREE` support in both API and engine V2 calculator routing.
- Confirm all three dispute bots are active. Funding alone does not confirm activation.
- Confirm engine RPC, migration, campaign indexing, calculator and root-update jobs are ready.
- Confirm HYPE and test-token aglaMerkl are registered, and aglaMerkl is allowed as a reward token.
- Choose a USDC holder for reward verification. Claim as that holder or an authorized operator.

## Simulate campaign creation

Run from the contracts repository with the existing Foundry toolchain. On the integration workstation, use its Nix shell.
Set `ETH_NODE_URI_99901` to the engine RPC endpoint for Elysium; it requires company network access.

```bash
export DEPLOYER_ADDRESS=0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701
export ELYSIUM_SMOKE_START=$(($(date +%s) + 1800))

forge script scripts/createElysiumSmokeCampaign.s.sol:CreateElysiumSmokeCampaign \
  --sig 'run(uint32)' "$ELYSIUM_SMOKE_START" \
  --rpc-url elysium \
  --legacy -vv
```

This command simulates only. It does not need a private key or send transactions.
Use `--legacy`: the configured provider does not support `eth_feeHistory`.

The script accepts the current contract terms if the operator has not already, approves exactly the reward budget unless an
existing predeposit covers it, and creates the campaign in the simulation.
It checks the chain, operator, start time, balance (wallet or predeposit), reward token allowance and minimum amount,
and the resulting campaign fields.

| Parameter | Value |
| --- | --- |
| Strategy | ERC20LOGPROCESSOR (18), time-weighted USDC balances |
| Target | `0xb47c4C8F73F009CC0C0d3f92B388d13E293F0B65` |
| Reward | aglaMerkl, `0x999BAcD74539e19e3371E51839707b59A682B258` |
| Budget | 10,000 aglaMerkl gross; decimals read from the token |
| Duration | 3,600 seconds |
| Eligibility | All USDC holders; no whitelist, blacklist, hooks or forwarders |
| Distribution | Default DUTCH_AUCTION with generic time-weighted balances |

The script prints the gross and net base units. The difference is the creation fee configured on the DistributionCreator.
Always use the actual stored net amount when checking rewards.
The printed simulation campaign ID is not a deployed campaign.

## Broadcast later

After the prerequisites are complete and the operator approves creation, rerun the same script with a fresh future start time,
the regular deployer signer, and `--broadcast`. Resolve `DEPLOYER_PRIVATE_KEY` through 1Password at execution time.
Do not use the Merkl deployer key. Do not broadcast a saved simulation with an expired start time.

Save the transaction hashes, creation block, campaign ID, start/end timestamps and actual net reward amount.
Confirm the transaction receipts succeed before proceeding.

## Verify indexing, computation and root publication

1. Find the campaign in the Merkl API: `GET /v4/campaigns/99901-<campaignId>`.
2. Confirm fetch registers indexing ranges and the campaign has an approved configuration, no unresolved pause and satisfied billing prerequisites.
3. Confirm indexing advances through the campaign interval and the V2 calculator selects this `TREE` campaign.
4. Confirm calculator output reconciles to the elapsed reward budget and, after completion, to the net budget including rounding.
5. Let the normal update job publish the root. Do not manually set a root to make the test pass.
6. Check `GET /v4/roots` with `chainId=99901`, `fromTimestamp` and `toTimestamp` covering the test.
7. Check the Distributor's `getMerkleRoot()` after the dispute period; it must match the claim proof's active root.
8. Verify TVL/APR using the configured prices; a mock token has no market price unless a test convention is explicitly configured.

## Simulate and verify a claim

Query the Merkl API user rewards endpoint (`GET /v4/users/<holder>/rewards`) with
`chainId=99901`, `test=true` and `claimableOnly=true`. The `test=true` filter is required because aglaMerkl is a test token.

Use the returned aglaMerkl cumulative amount and proof in the existing claim script:

```bash
DEPLOYER_ADDRESS=<holder-or-authorized-operator> \
forge script scripts/Distributor.s.sol:Claim \
  --sig 'run(address[],address[],uint256[],bytes32[][])' \
  '[<holder>]' \
  '[0x999BAcD74539e19e3371E51839707b59A682B258]' \
  '[<cumulative-amount>]' \
  '[[<proof-hashes>]]' \
  --rpc-url elysium \
  --legacy -vv
```

This command also simulates only. Do not use the pending amount or campaign-only amount in the proof.
After approval, broadcast with the authorized signer and confirm the receipt and `Claimed` event.
Verify the recipient receives the cumulative amount minus the previously claimed amount.
Refresh the API claim state and confirm an unchanged proof cannot produce a second payout.

Repeat campaign creation and claim through the frontend when the public RPC is available.
