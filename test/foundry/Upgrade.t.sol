// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { Test, stdError } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Distributor } from "../../contracts/Distributor.sol";

contract Upgrade is Test {
    Distributor distributor = Distributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);
    uint256 forkId;

    function setUp() public {
        forkId = vm.createFork(vm.envString("ETH_NODE_URI_OPTIMISM"));
    }

    function test_upgrade() public {
        vm.selectFork(forkId);

        (bool success, bytes memory data) = address(distributor).call(
            abi.encodeWithSelector(
                distributor.claimed.selector,
                0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185,
                0x4200000000000000000000000000000000000042
            )
        );
        (uint240 prevAmount, uint48 prevTimestamp) = abi.decode(data, (uint240, uint48));

        Distributor aux = new Distributor();
        vm.etch(address(distributor), address(aux).code);

        (success, data) = address(distributor).call(
            abi.encodeWithSelector(
                distributor.claimed.selector,
                0xfdA462548Ce04282f4B6D6619823a7C64Fdc0185,
                0x4200000000000000000000000000000000000042
            )
        );
        (uint240 amount, uint48 timestamp, bytes32 merklRoot) = abi.decode(data, (uint240, uint48, bytes32));

        assertEq(prevAmount, amount);
        assertGt(prevAmount, 0);
        assertEq(prevTimestamp, timestamp);
        assertGt(prevTimestamp, 0);
        assertEq(merklRoot, 0x0000000000000000000000000000000000000000000000000000000000000000);
    }
}
