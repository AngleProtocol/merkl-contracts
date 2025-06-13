// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { BusinessIdentifier } from "../contracts/utils/BusinessIdentifier.sol";

contract UpdateRedBelly is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BusinessIdentifier businessIdentifier = BusinessIdentifier(address(0xd6B69c81f36fD727602063217867E635C86A69a4));
        console.log("Business Identifier:", address(businessIdentifier));
        address[] memory delegates = new address[](6);
        delegates[0] = 0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002;
        delegates[1] = 0xf8b3b2aE2C97799249874A32f033b931e59fc349;
        delegates[2] = 0x34Eb88EAD486A09CAcD8DaBe013682Dc5F1DC41D;
        delegates[3] = 0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA;
        delegates[4] = 0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e;
        delegates[5] = 0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B;
        console.log("Batch limit", businessIdentifier.batchLimit());
        businessIdentifier.addAuthorisedDelegate(
            delegates
        );
        // Initialize
        vm.stopBroadcast();
    }
}
