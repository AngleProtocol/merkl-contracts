// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "forge-std/Script.sol";
import "../../contracts/example/MockAgEUR.sol";
import { console } from "forge-std/console.sol";

contract MyScript is Script {
    function test() external {
        vm.startBroadcast();

        MockAgEUR token = new MockAgEUR();
        address _sender = address(uint160(uint256(keccak256(abi.encodePacked("sender")))));
        address _receiver = address(uint160(uint256(keccak256(abi.encodePacked("receiver")))));

        console.log(address(token));

        // deal(address(token), _sender, 1 ether);
        // vm.prank(_sender);
        // token.transfer(_receiver, 1 ether);

        vm.stopBroadcast();
    }
}
