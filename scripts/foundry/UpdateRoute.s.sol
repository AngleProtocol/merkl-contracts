// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { Distributor, MerkleTree } from "contracts/Distributor.sol";
import { MockToken, IERC20 } from "contracts/mock/MockToken.sol";
import { CommonUtils, ContractType } from "utils/src/CommonUtils.sol";
import { CHAIN_BASE } from "utils/src/Constants.sol";
import { StdAssertions } from "forge-std/Test.sol";

contract UpdateRoute is CommonUtils, StdAssertions {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        /// TODO: COMPLETE
        uint256 chainId = CHAIN_BASE;
        MerkleTree memory newTree = MerkleTree({
            merkleRoot: 0xb402de8ed2f573c780a39e6d41aa5276706c439849d1e4925d379f2aa8913577,
            ipfsHash: bytes32(0)
        });
        address updater = 0x435046800Fb9149eE65159721A92cB7d50a7534b;
        /// END

        Distributor distributor = Distributor(_chainToContract(chainId, ContractType.Distributor));

        vm.startBroadcast(updater);

        distributor.updateTree(newTree);

        vm.stopBroadcast();

        // You then need to wait 1 hour to be effective
    }
}
