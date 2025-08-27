// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ContractType } from "@utils/Constants.sol";

import { PullTokenWrapperWithTransfer } from "../contracts/partners/tokenWrappers/PullTokenWrapperWithTransfer.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployPullTokenWrapperWithTransfer is BaseScript {
    // forge script scripts/deployPullTokenWrapperWithTransfer.s.sol --rpc-url katana --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify —verifier=blockscout   --verifier-url 'https://explorer.katanarpc.com/api/'
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Katana
        address underlying = 0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d;
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        address holder = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        // Keeping the same name and symbol as the original underlying token so it's invisible for users
        string memory name = "Katana Network Token (wrapped)";
        string memory symbol = "KAT";

        // Deploy implementation
        PullTokenWrapperWithTransfer implementation = new PullTokenWrapperWithTransfer();
        console.log("PullTokenWrapperWithTransfer Implementation:", address(implementation));
        /*
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("PullTokenWrapperWithTransfer Proxy:", address(proxy));

        // Initialize
        PullTokenWrapperWithTransfer(address(proxy)).initialize(underlying, distributionCreator, holder, name, symbol);

        PullTokenWrapperWithTransfer wkat = PullTokenWrapperWithTransfer(address(proxy));

        uint256 amount = 3000000 * 10 ** 18;
        address morphoCreator = 0xF057afeEc22E220f47AD4220871364e9E828b2e9;

        wkat.mint(amount); // Mint 3M KAT to the holder
        console.log("PullTokenWrapperWithTransfer Holder Balance:", IERC20(underlying).balanceOf(holder));
        wkat.setHolder(morphoCreator); // Set the holder to the Morpho creator address
        wkat.transfer(morphoCreator, amount);
        */

        vm.stopBroadcast();
    }
}
