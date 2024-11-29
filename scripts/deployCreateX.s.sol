// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { CreateXConstants } from "./utils/CreateXConstants.sol";

contract DeployCreateX is BaseScript, CreateXConstants {
    function run() public {
        // Uncomment to fund  (CreateX deployer address)
        uint256 DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 FUND_AMOUNT = 0.3 ether;
        if (CREATEX_DEPLOYER.balance == 0) {
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
            (bool success, ) = CREATEX_DEPLOYER.call{ value: FUND_AMOUNT }("");
            require(success, "Failed to fund CreateX deployer");
            vm.stopBroadcast();
        }

        // Broadcast the raw pre-signed transaction
        vm.broadcast(CREATEX_DEPLOYER);
        vm.broadcastRawTransaction(CREATEX_RAW_TX_3000000);
    }
}
