// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

import { MerklAdapter } from "../contracts/partners/MerklAdapter.sol";

/// @notice Deploys a `MerklAdapter` behind an ERC1967 proxy, atomically initialized in the proxy constructor.
contract DeployMerklAdapter is BaseScript {
    // forge script scripts/deployMerklAdapter.s.sol:DeployMerklAdapter --rpc-url <network> --sender <deployer> --broadcast --verify -vvvv
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // ------------------------------------------------------------------------
        // TO EDIT
        string memory name = "Merkl Adapter";
        string memory symbol = "mADP";
        // Asset managed by the adapter (must equal the underlying vault's asset()).
        address asset = 0x0000000000000000000000000000000000000000;
        // ERC4626 vault that assets are forwarded to.
        address underlyingVault = 0x0000000000000000000000000000000000000000;
        // Performance fee on interest, in BASE_18 (1e18 == 100%).
        uint256 performanceFee = 1e18;
        // Management fee as a per-second rate in BASE_18 (0 to disable).
        uint256 managementFee = 0;
        // Recipient of both fees.
        address feeRecipient = deployer;
        // Owner allowed to update fees and the fee recipient.
        address owner = deployer;
        // ------------------------------------------------------------------------

        require(asset != address(0), "asset not set");
        require(underlyingVault != address(0), "underlyingVault not set");

        // Deploy implementation
        address implementation = address(new MerklAdapter());
        console.log("MerklAdapter Implementation:", implementation);

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            MerklAdapter.initialize.selector,
            name,
            symbol,
            IERC20Upgradeable(asset),
            IERC4626Upgradeable(underlyingVault),
            performanceFee,
            managementFee,
            feeRecipient,
            owner
        );

        // Deploy proxy with initialization data (atomically initializes in the constructor)
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
        console.log("MerklAdapter Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
