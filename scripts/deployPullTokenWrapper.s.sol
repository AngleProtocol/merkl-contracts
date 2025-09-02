// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ContractType } from "@utils/Constants.sol";

import { PullTokenWrapper } from "../contracts/partners/tokenWrappers/PullTokenWrapper.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployPullTokenWrapper is BaseScript {
    // forge script scripts/deployPullTokenWrapper.s.sol --rpc-url zksync --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address underlying = 0xd6cD2c0fC55936498726CacC497832052A9B2D1B;
        address distributionCreator = 0xb2FFe1D404D284243a80BEa2D3DeB1a0108d9B9f;
        address holder = 0xdef1FA4CEfe67365ba046a7C630D6B885298E210;
        // Keeping the same name and symbol as the original underlying token so it's invisible for users
        string memory name = string(abi.encodePacked(IERC20Metadata(underlying).name(), " (wrapped)"));
        string memory symbol = IERC20Metadata(underlying).symbol();

        // Deploy implementation
        PullTokenWrapper implementation = new PullTokenWrapper();

        // Ethereum implementation
        // PullTokenWrapper implementation = PullTokenWrapper(0x979a04fd2f3A6a2B3945A715e24b974323E93567);

        console.log("PullTokenWrapper Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("PullTokenWrapper Proxy:", address(proxy));

        // Initialize
        PullTokenWrapper(address(proxy)).initialize(underlying, distributionCreator, holder, name, symbol);

        vm.stopBroadcast();
    }
}
