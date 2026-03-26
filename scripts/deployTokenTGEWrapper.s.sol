// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { TokenTGEWrapper } from "../contracts/partners/tokenWrappers/TokenTGEWrapper.sol";

contract DeployTokenTGEWrapper is BaseScript {
    // forge script scripts/deployTokenTGEWrapper.s.sol --rpc-url mainnet --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        // ------------------------------------------------------------------------
        // TO EDIT
        address underlying = 0x24A3D725C37A8D1a66Eb87f0E5D07fE67c120035;
        address holder = msg.sender;
        uint256 unlockTimestamp = 1772146800;
        // ------------------------------------------------------------------------

        TokenTGEWrapper wrapper = new TokenTGEWrapper(underlying, distributionCreator, holder, unlockTimestamp);

        console.log("TokenTGEWrapper:", address(wrapper));

        vm.stopBroadcast();
    }
}
