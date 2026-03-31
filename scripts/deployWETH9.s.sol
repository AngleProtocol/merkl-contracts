// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "../contracts/partners/tokenWrappers/weth9.sol";

contract DeployWETH9 is Script {
    WETH9 public weth9;
    uint256 private DEPLOYER_PRIVATE_KEY;

    function setUp() public {}

    function run() public {
        DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        weth9 = new WETH9(); 

        vm.stopBroadcast();
    }
}
