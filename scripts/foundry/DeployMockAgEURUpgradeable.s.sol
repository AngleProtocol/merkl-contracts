// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import { console } from "forge-std/console.sol";

import "../../../contracts/example/MockAgEUR.sol";

import "./Utils.s.sol";

contract DeployMockAgEURUpgradeable is Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.deriveKey(vm.envString("MNEMONIC_GOERLI"), 0);
        address deployer = vm.rememberKey(deployerPrivateKey);

        console.log("Deploying with ", deployer);

        vm.startBroadcast(deployer);

        MockAgEUR implementation = new MockAgEUR();
        deployUpgradeable(address(implementation), "");

        vm.stopBroadcast();
    }
}
