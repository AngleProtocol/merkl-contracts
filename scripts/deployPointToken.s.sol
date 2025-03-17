// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ContractType } from "@utils/Constants.sol";

import { PointToken } from "../contracts/partners/tokenWrappers/PointToken.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployPointToken is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address minter = 0x959680eded2c956A9Dd5184cD84D58497Cd41E0F;
        address accessControlManager = 0x05225a6416EDaeeC7227027E86F7A47D18A06b91;

        // Deploy implementation
        PointToken implementation = new PointToken("fake Apples","FA", minter,accessControlManager);
        console.log("PointToken Implementation:", address(implementation));

        // Initialize
        vm.stopBroadcast();
    }
}
