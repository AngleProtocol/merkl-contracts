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
        address user = address(0);
        address operator = address(0);
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
        address[] memory users = new address[](1);
        users[0] = 0xbDE3b37848dE5d26717fe27b4489E130E8d40e77;
        address[] memory tokens = new address[](1);
        tokens[0] = 0x471EcE3750Da237f93B8E339c536989b8978a438;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 40611295222190597472529;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](12);
        proofs[0][0] = 0xb8bfde09393d772b6c81e62ed70010edc95e5140ab52b7947f1f39caba379082;
        proofs[0][1] = 0xb1039b324c1e3616b94f8c0a1d3b41efbac06d59555e9ce5feab5429e4eb4c6e;
        proofs[0][2] = 0x20c00ba3347290bca8773e88209097fac1013d8fb2cf848b25f9f9b2a4587983;
        proofs[0][3] = 0x29b89499026c037c76d5070cb5adf8398ca2768ef3fb94c7cb666a8c200c91af;
        proofs[0][4] = 0x444732d59f5a702718ee03f936a099564ed014f9e448a9dfede9a1cec651c788;
        proofs[0][5] = 0xe5f133d0dd210e7f89adf739e87ef7fd5afbcdc230615c6a71c7d2c1a968d383;
        proofs[0][6] = 0xca5dc3bfa82c6249507c32080d440c7d34d8ac55dc26c3f28de114548891b0c4;
        proofs[0][7] = 0x45d4636913927f6fd6be6bdbfb536b7a37ec1f1efaac8552de1ea8f87da5d939;
        proofs[0][8] = 0x166232c805160aea4a86e0f2b32b21781521e7765ab5d13b4ae0b1af2d7ef893;
        proofs[0][9] = 0x7b12b41a38a9ad426fcdc06a405bb9fa2d01fbd93922adee141a3978ad28fa38;
        proofs[0][10] = 0x55b66cadfa2481cbacc1dd3f4812a1831553efd78ee48eaee75636d78d1c8409;
        proofs[0][11] = 0x00bade4967d60b3b661d932ae841a7b49b85f5088a4c7a9381510f2827716779;
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
