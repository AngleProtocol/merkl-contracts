// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PullTokenWrapperTransfer } from "../contracts/partners/tokenWrappers/PullTokenWrapperTransfer.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract DeployPullTokenWrapperTransfer is BaseScript {
    // forge script scripts/deployPullTokenWrapperTransfer.s.sol --rpc-url katana --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify —verifier=blockscout   --verifier-url 'https://explorer.katanarpc.com/api/'
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Katana
        address underlying = 0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d;
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        address minter = 0xb08AB4332AD871F89da24df4751968A61e58013c;
        // Keeping the same name and symbol as the original underlying token so it's invisible for users
        string memory name = "Katana Network Token (wrapped v2)";
        string memory symbol = "KAT";

        // Deploy implementation
        PullTokenWrapperTransfer implementation = new PullTokenWrapperTransfer();
        console.log("PullTokenWrapperTransfer Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("PullTokenWrapperTransfer Proxy:", address(proxy));

        // Initialize
        PullTokenWrapperTransfer(address(proxy)).initialize(underlying, distributionCreator, minter, name, symbol);

        address[] memory tokens;
        tokens[0] = address(proxy);

        uint256[] memory amounts;
        amounts[0] = 1e18;
        DistributionCreator(distributionCreator).setRewardTokenMinAmounts(tokens, amounts); // Set the minimum amount for the token wrapper

        vm.stopBroadcast();
    }
}
