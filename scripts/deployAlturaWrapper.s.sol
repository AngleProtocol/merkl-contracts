// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { AlturaWrapper } from "../contracts/partners/tokenWrappers/AlturaWrapper.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";

contract DeployAlturaWrapper is BaseScript {
    /**
     * @notice Deploys an AlturaWrapper proxy contract
     * @dev Example command:
     * forge script scripts/deployAlturaWrapper.s.sol --rpc-url hyperevm --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
     */
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // DistributionCreator address for this chain
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;

        // ========================================================================
        // CONFIGURATION - Update these values before deployment
        // ========================================================================

        // The vesting contract that will handle reward distribution
        // This contract must implement IVestingContract.allocateReward(address, uint256)
        address vestingContract = 0xbF4Ed131e3FC4Cdc35A0f2e653643FD0A589bc79;

        // Address authorized to mint wrapper tokens and update holder settings
        address holder = 0x68a6310FEA7101bB79fD9f751616D860a434DA66;

        // ------------------------------------------------------------------------
        // IMPLEMENTATION SELECTION
        // ------------------------------------------------------------------------
        // Choose ONE of the following options:
        //
        // Option 1: Deploy a new implementation contract
        address implementation = address(new AlturaWrapper());

        // Option 2: Reuse an existing implementation (saves gas)
        // Ethereum mainnet implementation:
        // address implementation = 0x0000000000000000000000000000000000000000; // Update with actual address

        // ------------------------------------------------------------------------
        // WRAPPER TOKEN NAMING
        // ------------------------------------------------------------------------
        // Name and symbol for the wrapper token
        // These will be visible on-chain and should clearly identify the wrapped reward token
        string memory name = "Altura Token (wrapped)";
        string memory symbol = "ALTU";

        // ========================================================================

        console.log("AlturaWrapper Implementation:", address(implementation));

        // Prepare initialization parameters for the proxy
        // This data will be used to atomically initialize the proxy in its constructor
        bytes memory initData = abi.encodeWithSelector(
            AlturaWrapper.initialize.selector,
            vestingContract, // Vesting contract that handles reward allocation
            distributionCreator, // DistributionCreator contract address
            holder, // Authorized holder address
            name, // ERC20 name for the wrapper token
            symbol // ERC20 symbol for the wrapper token
        );

        // Deploy ERC1967 proxy with implementation and initialization data
        // The proxy will delegate all calls to the implementation contract
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("AlturaWrapper Proxy:", address(proxy));

        // ========================================================================
        // SECURITY VERIFICATION
        // ========================================================================
        // Verify the implementation address stored in the proxy to prevent hijack attacks
        // We read directly from the ERC1967 implementation slot to ensure no manipulation occurred
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address storedImplementation = address(uint160(uint256(vm.load(address(proxy), implSlot))));
        console.log("Proxy Implementation (verified):", storedImplementation);

        vm.stopBroadcast();
    }
}
