// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ContractType } from "@utils/Constants.sol";

import { PullTokenWrapperAllow } from "../contracts/partners/tokenWrappers/PullTokenWrapperAllow.sol";
import { PullTokenWrapperWithdraw } from "../contracts/partners/tokenWrappers/PullTokenWrapperWithdraw.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployPullTokenWrapper is BaseScript {
    // forge script scripts/deployPullTokenWrapper.s.sol --rpc-url mainnet --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        // ------------------------------------------------------------------------
        // TO EDIT
        address underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        address holder = 0x304C9C032a82Ca287C1681EA68189f8C0De5746d;

        // Need to choose the implementation type and if implementation needs to be deployed
        // address implementation = address(new PullTokenWrapperWithdraw());
        // address implementation = address(new PullTokenWrapperAllow());
        // Ethereum implementation of PullTokenWrapperAllow
        address implementation = 0x979a04fd2f3A6a2B3945A715e24b974323E93567;
        // Ethereum implementation of PullTokenWrapperWithdraw
        // address implementation = 0x721d37cf37e230E120a09adbBB7aAB0CF729AcA1

        // Keeping the same name and symbol as the original underlying token so it's invisible for users
        string memory name = string(abi.encodePacked(IERC20Metadata(underlying).name(), " (wrapped)"));
        string memory symbol = IERC20Metadata(underlying).symbol();

        // Names to override if deploying a PullTokenWrapperWithdraw implementation
        // name = "USDT0 (wrapped)";
        // symbol = "USDT0";

        // ------------------------------------------------------------------------

        console.log("PullTokenWrapper Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("PullTokenWrapper Proxy:", address(proxy));

        // Initialize
        PullTokenWrapperAllow(address(proxy)).initialize(underlying, distributionCreator, holder, name, symbol);

        vm.stopBroadcast();
    }
}
