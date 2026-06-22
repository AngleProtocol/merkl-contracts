// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { MockToken } from "../contracts/mock/MockToken.sol";
import { PullTokenWrapperAllowImmutable } from "../contracts/partners/tokenWrappers/PullTokenWrapperAllowImmutable.sol";

contract DeployMockTokenAndWrapper is BaseScript {
    // forge script scripts/deployMockTokenAndWrapper.s.sol --rpc-url arbitrum --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // ------------------------------------------------------------------------
        // TO EDIT
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        address holder = 0x522e74071e047B7B234444B5f3bB6eF0D535F3b4;
        string memory name = "AglaMerkl USD";
        string memory symbol = "aglaMerklUSD";
        uint8 decimals = 18;
        uint256 mintAmount = 1_000_000_000 * 10 ** 18; // 1bn
        uint256 wrapperMintAmount = 1_000_000 * 10 ** 18; // 1m
        // ------------------------------------------------------------------------

        MockToken token = new MockToken(name, symbol, decimals);
        console.log("MockToken:", address(token));

        token.mint(deployer, mintAmount);
        console.log("Minted %s to %s", mintAmount, deployer);

        token.mint(holder, mintAmount);
        console.log("Minted %s to %s", mintAmount, holder);
        /*

        PullTokenWrapperAllowImmutable wrapper = new PullTokenWrapperAllowImmutable(
            address(token),
            distributionCreator,
            deployer
        );
        console.log("PullTokenWrapperAllowImmutable:", address(wrapper));

        wrapper.mint(deployer, wrapperMintAmount);
        console.log("Minted %s wrapper tokens to deployer %s", wrapperMintAmount, deployer);

        wrapper.mint(holder, wrapperMintAmount);
        console.log("Minted %s wrapper tokens to holder %s", wrapperMintAmount, holder);
        */

        vm.stopBroadcast();
    }
}
