// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { BaseScript } from "./utils/Base.s.sol";

interface IWETH98 {
    function deposit() external payable;
    function balanceOf(address) external view returns (uint256);
}

contract DepositWETH is BaseScript {
    address constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
    uint256 constant DEPOSIT_AMOUNT = 0.01 ether;

    function run() public broadcast {
        IWETH98 weth = IWETH98(WETH_ADDRESS);

        console.log("Depositing", DEPOSIT_AMOUNT, "ETH to WETH at", WETH_ADDRESS);
        console.log("Sender:", broadcaster);
        console.log("Sender ETH balance:", broadcaster.balance);

        uint256 balanceBefore = weth.balanceOf(broadcaster);
        console.log("WETH balance before:", balanceBefore);

        weth.deposit{ value: DEPOSIT_AMOUNT }();

        uint256 balanceAfter = weth.balanceOf(broadcaster);
        console.log("WETH balance after:", balanceAfter);
        console.log("Successfully deposited", balanceAfter - balanceBefore, "WETH");
    }
}
