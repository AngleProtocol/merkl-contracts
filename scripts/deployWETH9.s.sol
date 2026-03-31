// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {WETH9} from "../contracts/partners/tokenWrappers/weth9.sol";

contract CounterScript is Script {
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
