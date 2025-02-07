// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { BaseScript } from "./utils/Base.s.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
interface IDistributionCreator {
    function distributor() external view returns (address);

    function feeRecipient() external view returns (address);

    function accessControlManager() external view returns (IAccessControlManager);
}

contract DeployReferralRegistry is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        uint256 feeSetup = 0;
        // uint32 cliffDuration = 1 weeks;
        IDistributionCreator distributionCreator = IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
        address feeRecipient = distributionCreator.feeRecipient();
        IAccessControlManager accessControlManager = distributionCreator.accessControlManager();

        // Deploy implementation
        address implementation = address(new ReferralRegistry());
        console.log("ReferralRegistry Implementation:", implementation);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, "");
        console.log("ReferralRegistry Proxy:", address(proxy));

        // Initialize
        ReferralRegistry(payable(address(proxy))).initialize(accessControlManager, feeSetup, feeRecipient);
        vm.stopBroadcast();
    }
}
