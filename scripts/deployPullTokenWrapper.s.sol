// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ContractType } from "@utils/Constants.sol";

import { PullTokenWrapper } from "../contracts/partners/tokenWrappers/PullTokenWrapper.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployPullTokenWrapper is BaseScript {
    // forge script scripts/deployPullTokenWrapper.s.sol --rpc-url linea --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // aUSDe
        address underlying = 0x0C7921aB4888fd06731898b3fffFeB06781D5F4F;
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        address holder = 0xdef1FA4CEfe67365ba046a7C630D6B885298E210;
        // Keeping the same name and symbol as the original underlying token so it's invisible for users
        string memory name = "Aave Linea weETH (wrapped)";
        string memory symbol = "aLinweETH";

        // Deploy implementation
        PullTokenWrapper implementation = new PullTokenWrapper();
        // PullTokenWrapper implementation = PullTokenWrapper(0x2c63f9da936624Ac7313b972251D340260A4bF08);
        console.log("PullTokenWrapper Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("PullTokenWrapper Proxy:", address(proxy));

        // Initialize
        PullTokenWrapper(address(proxy)).initialize(underlying, distributionCreator, holder, name, symbol);

        vm.stopBroadcast();
    }
}
