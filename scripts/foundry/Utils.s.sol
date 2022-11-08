// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "forge-std/Script.sol";
import "../../contracts/example/MockAgEUR.sol";
import "../../contracts/proxy/ProxyAdmin.sol";
import "../../contracts/proxy/TransparentUpgradeableProxy.sol";

import { console } from "forge-std/console.sol";

contract Utils is Script {
    address public constant PROXY_ADMIN = 0x1D941EF0D3Bba4ad67DBfBCeE5262F4CEE53A32b;

    function deployUpgradeable(address implementation, bytes memory data) public returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, PROXY_ADMIN, data));
    }
}
