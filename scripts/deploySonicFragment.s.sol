// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { console } from "forge-std/console.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SonicFragment } from "../contracts/partners/tokenWrappers/SonicFragment.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

// forge script scripts/deploySonicFragment.s.sol:DeploySonicFragment --rpc-url sonic --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --verify -vvvv --broadcast -i 1
contract DeploySonicFragment is BaseScript {
    function run() public broadcast {
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Sonic address - to check
        IAccessControlManager manager = IAccessControlManager(0xa25c30044142d2fA243E7Fd3a6a9713117b3c396);
        address recipient = address(broadcaster);
        // TODO this is the wrapped Sonic address
        address sToken = address(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
        uint256 totalSupply = 10_000_000 ether;
        string memory name = "TEST GEM";
        string memory symbol = "testGEM-S1";

        // Deploy implementation
        SonicFragment implementation = new SonicFragment(address(manager), recipient, sToken, totalSupply, name, symbol);
        console.log("SonicFragment deployed at:", address(implementation));
    }
}
