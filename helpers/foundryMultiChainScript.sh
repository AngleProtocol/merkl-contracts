#! /bin/bash

function usage {
  echo "bash foundryMultiChainScript.sh <foundry-script-path>"
  echo "Lists all chains where Merkl DistributionCreator is deployed and allows selection"
  echo "Example: bash foundryMultiChainScript.sh ./scripts/DistributionCreator.s.sol:UpgradeAndBuildUpgradeToPayload"
  echo ""
}

# Get list of chain IDs where DistributionCreator is deployed
function get_available_chains() {
    local registry_file="node_modules/@merkl/registry/dist/src/registry.json"
    if [ ! -f "$registry_file" ]; then
        echo "Registry file not found!"
        exit 1
    fi

    jq -r 'to_entries | .[] | select(.value.Merkl.DistributionCreator != null) | .key' "$registry_file"
}

# Get list of chains to deploy to, handling exclusions
function get_selected_chains() {
    local chain_ids=("$@")
    local selected_chains=()
    local exclude_chain_ids=(314)  # Default exclusions: filecoin

    read -p "Do you want to run the script on all chains? (y/n) -- Note: ChainIDs 314 and 324 is already excluded by default: " deploy_all

    if [[ "$deploy_all" == "y" ]]; then
        for chain_id in "${chain_ids[@]}"; do
            if [[ ! " ${exclude_chain_ids[@]} " =~ " ${chain_id} " ]]; then
                selected_chains+=("$chain_id")
            fi
        done
    else
        read -p "Enter chain IDs to exclude (space-separated), or press enter to continue: " -a additional_exclude
        exclude_chain_ids+=("${additional_exclude[@]}")

        for chain_id in "${chain_ids[@]}"; do
            if [[ ! " ${exclude_chain_ids[@]} " =~ " ${chain_id} " ]]; then
                selected_chains+=("$chain_id")
            fi
        done
    fi

    printf "%s " "${selected_chains[@]}"
}

# Get verification string for a specific chain
function get_verify_string() {
    local chain_id=$1
    local verify_string=""
    
    local verifier_type_var="VERIFIER_TYPE_${chain_id}"
    local verifier_type=$(eval "echo \$$verifier_type_var")
    
    if [ ! -z "${verifier_type}" ]; then
        verify_string="--verify --verifier ${verifier_type}"
        
        # Add verifier URL if present
        local verifier_url_var="VERIFIER_URL_${chain_id}"
        local verifier_url=$(eval "echo \$$verifier_url_var")
        if [ ! -z "${verifier_url}" ]; then
            verify_string="${verify_string} --verifier-url ${verifier_url}"
        fi
        
        # Add API key if present
        local verifier_api_key_var="VERIFIER_API_KEY_${chain_id}"
        local verifier_api_key=$(eval "echo \$$verifier_api_key_var")
        if [ ! -z "${verifier_api_key}" ]; then
            if [ "${verifier_type}" == "etherscan" ]; then
                verify_string="${verify_string} --etherscan-api-key ${verifier_api_key}"
            else
                verify_string="${verify_string} --verifier-api-key ${verifier_api_key}"
            fi
        fi
    fi
    
    echo "$verify_string"
}

# Get compilation flags for a specific chain
function get_compile_flags() {
    local chain_id=$1
    
    london_chain_ids=(30 122 592 1284 1923 10242 108 250 42220 59144)
    legacy_chain_ids=(196 250 1329 3776 480 2046399126 42793)
    zk_chain_ids=(324)
    if [[ " ${london_chain_ids[@]} " =~ " ${chain_id} " ]]; then
        echo "--evm-version london"
    elif [[ " ${legacy_chain_ids[@]} " =~ " ${chain_id} " ]]; then
        echo "--legacy"
    elif [[ " ${zk_chain_ids[@]} " =~ " ${chain_id} " ]]; then
        echo "--zksync"
    else
        echo ""
    fi
}

function main {
    # Check if script path is provided
    if [ -z "$1" ]; then
        usage
        exit 1
    fi
    
    FOUNDRY_SCRIPT="$1"
    
    # Verify the script exists
    if [ ! -f "$FOUNDRY_SCRIPT" ]; then
        echo "Error: Script file '$FOUNDRY_SCRIPT' not found!"
        exit 1
    fi

    # Path to the registry file
    registry_file="node_modules/@merkl/registry/dist/src/registry.json"

    if [ ! -f "$registry_file" ]; then
        echo "Registry file not found!"
        exit 1
    fi


    # Store chain IDs in an array
    chain_ids=()
    while IFS= read -r chain_id; do
        chain_ids+=("$chain_id")
    done <<< "$(jq -r 'to_entries | .[] | select(.value.Merkl.DistributionCreator != null) | .key' "$registry_file")"

    # Display all chains
    echo "Chain IDs where Merkl DistributionCreator is deployed: ${chain_ids[@]}"

    echo ""
    selected_chains=($(get_selected_chains "${chain_ids[@]}"))

    source .env
    rm -f ./transaction.json

    # Initialize arrays for tracking deployment status
    successful_chains=()
    failed_chains=()

    # Prompt user for broadcast and verify options
    read -p "Do you want to broadcast the transaction? (y/n): " broadcast_choice

    # Set flags based on user input
    if [ "$broadcast_choice" == "y" ]; then
        broadcast_flag="--broadcast"
        read -p "Do you want to verify the transaction? (y/n): " verify_choice
    else
        broadcast_flag=""
    fi

    # Run forge script for each selected chain
    for chain_id in "${selected_chains[@]}"; do
        echo "Running forge script for chain ID: $chain_id"
        rpc_url_var="ETH_NODE_URI_${chain_id}"
        rpc_url=$(eval "echo \$$rpc_url_var")
        
        # Check if chain ID already exists in transactions.json
        if [ -f "./transactions.json" ] && jq -e "has(\"$chain_id\")" ./transactions.json > /dev/null; then
            echo "Chain ID $chain_id already exists in transactions.json, skipping..."
            continue
        fi

        # Verification string based on chain-specific environment variables
        if [ "$verify_choice" == "y" ]; then
            verify_string=$(get_verify_string "$chain_id")
        else
            verify_string=""
        fi

        # Compilation specific flags
        compile_flags=$(get_compile_flags "$chain_id")

        cmd="forge script $FOUNDRY_SCRIPT $broadcast_flag --rpc-url $rpc_url $compile_flags $verify_string --force"
        echo "Running command: $cmd"
        if eval $cmd && [ -f "./transaction.json" ]; then
            successful_chains+=("$chain_id")
        else
            failed_chains+=("$chain_id")
        fi

        # Create a new JSON object with chain ID as key and transaction data as value
        if [ -f "./transaction.json" ]; then
            jq -s '.[0] * {("'$chain_id'"): .[1]}' \
                ./transactions.json \
                ./transaction.json > ./transactions.json.tmp
            
            mv ./transactions.json.tmp ./transactions.json
            rm -f ./transaction.json
        fi

        # Add verification step if verification was requested
        if [ "$verify_choice" == "y" ]; then
            echo "Attempting contract verification..."
            # Extract contract address from the data field (removing 0x3659cfe6 prefix and any leading zeros)
            contract_address=$(jq -r --arg chainid "$chain_id" '.[$chainid].data' ./transactions.json | sed 's/^0x3659cfe6000000000000000000000000//')
            
            if [ ! -z "$contract_address" ] && [ "$contract_address" != "null" ]; then
                # Get verification parameters from environment variables
                verify_flag=$(get_verify_string "$chain_id" | sed 's/--verify //')
                compile_flags=$(get_compile_flags "$chain_id" | sed 's/--legacy //')
                verify_cmd="forge verify-contract --rpc-url $rpc_url 0x$contract_address contracts/DistributionCreator.sol:DistributionCreator $verify_flag $compile_flags --watch"
                echo "Running verification command: $verify_cmd"
                if eval $verify_cmd; then
                    echo "✅ Contract verification successful"
                else
                    echo "❌ Contract verification failed"
                fi
            fi
        fi

        echo "Safe to cancel job for 5 seconds"
        sleep 5
        echo "Starting next chain"
    done

    # Display final deployment status
    if [ ${#successful_chains[@]} -gt 0 ]; then
        echo -e "\n✅ Deployment successful on chains: ${successful_chains[*]}"
    fi
    if [ ${#failed_chains[@]} -gt 0 ]; then
        echo -e "\n❌ Deployment issues on chains: ${failed_chains[*]}"
    fi
}

main "$@"