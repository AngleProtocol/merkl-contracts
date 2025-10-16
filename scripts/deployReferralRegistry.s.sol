// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { BaseScript } from "./utils/Base.s.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";

contract DeployReferralRegistry is BaseScript {
    // forge script scripts/deployReferralRegistry.s.sol:DeployReferralRegistry --rpc-url avalanche --broadcast --verify -vvvv
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        uint256 feeSetup = 0;
        // uint32 cliffDuration = 1 weeks;
        DistributionCreator distributionCreator = DistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
        address feeRecipient = distributionCreator.feeRecipient();
        IAccessControlManager accessControlManager = distributionCreator.accessControlManager();

        // Deploy implementation
        /*
        address implementation = address(new ReferralRegistry());
        console.log("ReferralRegistry Implementation:", implementation);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, "");
        console.log("ReferralRegistry Proxy:", address(proxy));

        // Initialize
        ReferralRegistry(payable(address(proxy))).initialize(accessControlManager, feeSetup, feeRecipient);

*/
        string memory key = "avant-referral";

        ReferralRegistry(payable(0x3FB2121208b40c7878089A78cc58f9b4D9D8b9F4)).addReferralKey(
            key,
            0,
            false,
            0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701,
            false,
            address(0)
        );

        vm.stopBroadcast();
    }
}
