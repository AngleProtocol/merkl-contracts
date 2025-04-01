// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { Distributor, MerkleTree } from "../contracts/Distributor.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";

// Base contract with shared utilities
contract DistributorScript is BaseScript, JsonReader {}

// Deploy script
contract Deploy is DistributorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        address accessControlManager = readAddress(chainId, "Merkl.CoreMerkl");

        // Deploy implementation
        Distributor implementation = new Distributor();
        console.log("Distributor Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("Distributor Proxy:", address(proxy));

        // Initialize
        Distributor(address(proxy)).initialize(IAccessControlManager(accessControlManager));
    }
}

// UpdateTree script
contract UpdateTree is DistributorScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED TREE PARAMETERS
        bytes32 merkleRoot = bytes32(0);
        bytes32 ipfsHash = bytes32(0);
        _run(merkleRoot, ipfsHash);
    }

    function run(bytes32 merkleRoot, bytes32 ipfsHash) external broadcast {
        _run(merkleRoot, ipfsHash);
    }

    function _run(bytes32 merkleRoot, bytes32 ipfsHash) internal {
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
    function run() external broadcast {
        // MODIFY THIS VALUE TO SET YOUR DESIRED REASON
        string memory reason = "reason";
        _run(reason);
    }

    function run(string calldata reason) external broadcast {
        _run(reason);
    }

    function _run(string memory reason) internal {
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
    function run() external broadcast {
        // MODIFY THIS VALUE TO SET YOUR DESIRED VALIDITY
        bool valid = false;
        _run(valid);
    }

    function run(bool valid) external broadcast {
        _run(valid);
    }

    function _run(bool valid) internal {
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
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED USER AND OPERATOR
        // forge script scripts/Distributor.s.sol:ToggleOperator --rpc-url berachain --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast -i 1
        address user = address(0xe2843F0148Ab7de33Ce85DE433850F5f68b46331);
        address operator = address(0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701);
        _run(user, operator);
    }

    function run(address user, address operator) external broadcast {
        _run(user, operator);
    }

    function _run(address user, address operator) internal {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).toggleOperator(user, operator);

        console.log("Toggled operator:", operator, "for user:", user);
    }
}

// RecoverERC20 script
contract RecoverERC20 is DistributorScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED TOKEN, RECIPIENT AND AMOUNT
        address token = address(0);
        address to = address(0);
        uint256 amount = 0;
        _run(token, to, amount);
    }

    function run(address token, address to, uint256 amount) external broadcast {
        _run(token, to, amount);
    }

    function _run(address token, address to, uint256 amount) internal {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).recoverERC20(token, to, amount);

        console.log("Recovered %s of token %s to %s", amount, token, to);
    }
}

// SetDisputeToken script
contract SetDisputeToken is DistributorScript {
    function run() external broadcast {
        // MODIFY THIS VALUE TO SET YOUR DESIRED TOKEN
        IERC20 token = IERC20(address(0));
        _run(token);
    }

    function run(IERC20 token) external broadcast {
        _run(token);
    }

    function _run(IERC20 token) internal {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).setDisputeToken(token);

        console.log("Dispute token updated to:", address(token));
    }
}

// SetDisputeAmount script
contract SetDisputeAmount is DistributorScript {
    function run() external broadcast {
        // MODIFY THIS VALUE TO SET YOUR DESIRED AMOUNT
        uint256 amount = 0;
        _run(amount);
    }

    function run(uint256 amount) external broadcast {
        _run(amount);
    }

    function _run(uint256 amount) internal {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).setDisputeAmount(amount);

        console.log("Dispute amount updated to:", amount);
    }
}

// SetDisputePeriod script
contract SetDisputePeriod is DistributorScript {
    function run() external broadcast {
        // MODIFY THIS VALUE TO SET YOUR DESIRED PERIOD
        uint48 period = 0;
        _run(period);
    }

    function run(uint48 period) external broadcast {
        _run(period);
    }

    function _run(uint48 period) internal {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).setDisputePeriod(period);

        console.log("Dispute period updated to:", period);
    }
}

// ToggleTrusted script
contract ToggleTrusted is DistributorScript {
    function run() external broadcast {
        // MODIFY THIS VALUE TO SET YOUR DESIRED EOA
        address eoa = address(0);
        _run(eoa);
    }

    function run(address eoa) external broadcast {
        _run(eoa);
    }

    function _run(address eoa) internal {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).toggleTrusted(eoa);

        console.log("Toggled trusted status for:", eoa);
    }
}

// Claim script
contract Claim is DistributorScript {
    function run() external broadcast {
        // MODIFY THESE VALUES TO SET YOUR DESIRED CLAIM PARAMETERS
        address[] memory users = new address[](0);
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        bytes32[][] memory proofs = new bytes32[][](0);
        _run(users, tokens, amounts, proofs);
    }

    function run(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external broadcast {
        _run(users, tokens, amounts, proofs);
    }

    function _run(
        address[] memory users,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes32[][] memory proofs
    ) internal {
        uint256 chainId = block.chainid;
        address distributorAddress = readAddress(chainId, "Merkl.Distributor");

        Distributor(distributorAddress).claim(users, tokens, amounts, proofs);

        console.log("Claimed rewards for", users.length, "users");
    }
}

contract BuildUpgradeToPayload is DistributorScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        address distributor = readAddress(chainId, "Merkl.Distributor");

        address distributorImpl = address(new Distributor());

        bytes memory payload = abi.encodeWithSelector(ITransparentUpgradeableProxy.upgradeTo.selector, distributorImpl);

        try this.externalReadAddress(chainId, "AngleLabs") returns (address safe) {
            _serializeJson(
                chainId,
                distributor, // target address (the proxy)
                0, // value
                payload, // direct upgrade call
                Operation.Call, // standard call (not delegate)
                hex"", // signature
                safe // safe address
            );
        } catch {}
    }

    function externalReadAddress(uint256 chainId, string memory key) external view returns (address) {
        return readAddress(chainId, key);
    }
}
