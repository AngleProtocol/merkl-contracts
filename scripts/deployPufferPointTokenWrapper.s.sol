// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PufferPointTokenWrapper } from "../contracts/partners/tokenWrappers/PufferPointTokenWrapper.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployPufferPointTokenWrapper is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address underlying = 0x282A69142bac47855C3fbE1693FcC4bA3B4d5Ed6;
        uint32 cliffDuration = 500;
        // uint32 cliffDuration = 1 weeks;
        IAccessControlManager manager = IAccessControlManager(0x0E632a15EbCBa463151B5367B4fCF91313e389a6);
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;

        // ARBITRUM TEST
        /*
        // aglaMerkl
        address underlying = 0xE0688A2FE90d0f93F17f273235031062a210d691;
        uint32 cliffDuration = 500;
        // uint32 cliffDuration = 1 weeks;
        IAccessControlManager manager = IAccessControlManager(0xA86CC1ae2D94C6ED2aB3bF68fB128c2825673267);
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        */

        // Deploy implementation
        PufferPointTokenWrapper implementation = new PufferPointTokenWrapper();
        console.log("PufferPointTokenWrapper Implementation:", address(implementation));
        /*
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("PufferPointTokenWrapper Proxy:", address(proxy));

        // Initialize
        PufferPointTokenWrapper(address(proxy)).initialize(underlying, cliffDuration, manager, distributionCreator);
        */
        vm.stopBroadcast();
    }
}
