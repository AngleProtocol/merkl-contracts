// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { TokenTGEWrapper } from "../contracts/partners/tokenWrappers/TokenTGEWrapper.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployTokenTGEWrapper is BaseScript {
    // forge script scripts/deployTokenTGEWrapper.s.sol --rpc-url mainnet --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        // ------------------------------------------------------------------------
        // TO EDIT
        address underlying = 0x24A3D725C37A8D1a66Eb87f0E5D07fE67c120035;
        // ------------------------------------------------------------------------

        address implementation = address(new TokenTGEWrapper());

        console.log("Wrapper Implementation:", address(implementation));

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            TokenTGEWrapper.initialize.selector,
            underlying,
            1772146800,
            distributionCreator
        );

        // Deploy proxy with initialization data (atomically initializes in constructor)
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Wrapper Proxy:", address(proxy));

        // Read and log the implementation address from the proxy to avoid hijack attacks
        // ERC1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address storedImplementation = address(uint160(uint256(vm.load(address(proxy), implSlot))));
        console.log("Proxy Implementation (verified):", storedImplementation);

        vm.stopBroadcast();
    }
}
