// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "../utils/Base.s.sol";
import { Distributor, MerkleTree } from "../../contracts/Distributor.sol";
import { JsonReader } from "../utils/JsonReader.sol";
import { ICore } from "../../contracts/interfaces/ICore.sol";

// Base contract with shared utilities
contract DistributorScript is BaseScript, JsonReader {}

// Deploy script
contract Deploy is DistributorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Read configuration from JSON
        address angleLabs = readAddress(chainId, "AngleLabs");
        address core = readAddress(chainId, "Core");

        // Deploy implementation
        Distributor implementation = new Distributor();
        console.log("Distributor Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("Distributor Proxy:", address(proxy));

        // Initialize
        Distributor(address(proxy)).initialize(ICore(core));
    }
}

// UpdateTree script
contract UpdateTree is DistributorScript {
    function run(bytes32 merkleRoot, bytes32 ipfsHash) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        MerkleTree memory newTree = MerkleTree({ merkleRoot: merkleRoot, ipfsHash: ipfsHash });

        Distributor(distributorAddress).updateTree(newTree);

        console.log("Tree updated with root:", vm.toString(merkleRoot));
        console.log("IPFS Hash:", vm.toString(ipfsHash));
    }
}

// DisputeTree script
contract DisputeTree is DistributorScript {
    function run(string calldata reason) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        // Get dispute token and amount from the distributor
        IERC20 disputeToken = Distributor(distributorAddress).disputeToken();
        uint256 disputeAmount = Distributor(distributorAddress).disputeAmount();

        // Check current allowance
        uint256 currentAllowance = disputeToken.allowance(broadcaster, distributorAddress);
        if (currentAllowance < disputeAmount) {
            disputeToken.approve(distributorAddress, disputeAmount);
        }

        Distributor(distributorAddress).disputeTree(reason);

        console.log("Tree disputed with reason:", reason);
    }
}

// ResolveDispute script
contract ResolveDispute is DistributorScript {
    function run(bool valid) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).resolveDispute(valid);

        console.log("Dispute resolved with validity:", valid);
    }
}

// RevokeTree script
contract RevokeTree is DistributorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).revokeTree();

        console.log("Tree revoked");
    }
}

// ToggleOperator script
contract ToggleOperator is DistributorScript {
    function run(address user, address operator) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).toggleOperator(user, operator);

        console.log("Toggled operator:", operator, "for user:", user);
    }
}

// RecoverERC20 script
contract RecoverERC20 is DistributorScript {
    function run(address token, address to, uint256 amount) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).recoverERC20(token, to, amount);

        console.log("Recovered %s of token %s to %s", amount, token, to);
    }
}

// SetDisputeToken script
contract SetDisputeToken is DistributorScript {
    function run(IERC20 token) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).setDisputeToken(token);

        console.log("Dispute token updated to:", address(token));
    }
}

// SetDisputeAmount script
contract SetDisputeAmount is DistributorScript {
    function run(uint256 amount) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).setDisputeAmount(amount);

        console.log("Dispute amount updated to:", amount);
    }
}

// SetDisputePeriod script
contract SetDisputePeriod is DistributorScript {
    function run(uint48 period) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).setDisputePeriod(period);

        console.log("Dispute period updated to:", period);
    }
}

// ToggleTrusted script
contract ToggleTrusted is DistributorScript {
    function run(address eoa) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).toggleTrusted(eoa);

        console.log("Toggled trusted status for:", eoa);
    }
}

// Claim script
contract Claim is DistributorScript {
    function run(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).claim(users, tokens, amounts, proofs);

        console.log("Claimed rewards for", users.length, "users");
    }
}

// ToggleOnlyOperatorCanClaim script (deprecated but included for completeness)
contract ToggleOnlyOperatorCanClaim is DistributorScript {
    function run(address user) external broadcast {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).toggleOnlyOperatorCanClaim(user);

        console.log("Toggled operator-only claiming for user:", user);
    }
}
