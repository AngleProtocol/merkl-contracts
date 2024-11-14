// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CoreBorrow } from "../../contracts/core/CoreBorrow.sol";
import { Distributor } from "../../contracts/Distributor.sol";
import { DistributionCreator } from "../../contracts/DistributionCreator.sol";
import { console } from "forge-std/console.sol";
import { JsonReader } from "../utils/JsonReader.sol";
import { ICore } from "../../contracts/interfaces/ICore.sol";
import { BaseScript } from "../utils/Base.s.sol";

contract MainDeployScript is Script, BaseScript {
    // Constants and storage
    address public ANGLE_LABS;
    address public DEPLOYER_ADDRESS;
    JsonReader public reader;

    struct DeploymentAddresses {
        address proxy;
        address implementation;
    }

    function run() external broadcast {
        // Setup
        reader = new JsonReader();
        console.log("Chain ID:", block.chainid);

        ANGLE_LABS = reader.readAddress(block.chainid, "angleLabs");
        console.log("ANGLE_LABS:", ANGLE_LABS);

        DEPLOYER_ADDRESS = broadcaster;
        console.log("DEPLOYER_ADDRESS:", DEPLOYER_ADDRESS);

        // Deploy CoreBorrow
        console.log("\n=== Deploying CoreBorrow ===");
        DeploymentAddresses memory coreBorrow = deployCoreBorrow();
        console.log("CoreBorrow deployed at:", coreBorrow.proxy);

        // Deploy Distributor
        console.log("\n=== Deploying Distributor ===");
        DeploymentAddresses memory distributor = deployDistributor(coreBorrow.proxy);
        console.log("Distributor deployed at:", distributor.proxy);

        // Deploy DistributionCreator
        console.log("\n=== Deploying DistributionCreator ===");
        DeploymentAddresses memory creator = deployDistributionCreator(coreBorrow.proxy, distributor.proxy);
        console.log("DistributionCreator deployed at:", creator.proxy);

        // Print summary
        console.log("\n=== Deployment Summary ===");
        console.log("CoreBorrow:");
        console.log("  - Proxy:", coreBorrow.proxy);
        console.log("  - Implementation:", coreBorrow.implementation);
        console.log("Distributor:");
        console.log("  - Proxy:", distributor.proxy);
        console.log("  - Implementation:", distributor.implementation);
        console.log("DistributionCreator:");
        console.log("  - Proxy:", creator.proxy);
        console.log("  - Implementation:", creator.implementation);

        console.log("\n=== Additional Setup Required ===");
        console.log("On DistributionCreator:");
        console.log("- setRewardTokenMinAmounts()");
        console.log("- setFeeRecipient() -> angleLabs");
        console.log("- setMessage()");
        console.log("\nOn Distributor:");
        console.log("- toggleTrusted() -> keeper bot updating");
        console.log("- setDisputeToken()");
        console.log("- setDisputePeriod()");
        console.log("- setDisputeAmount()");
    }

    function deployCoreBorrow() public returns (DeploymentAddresses memory) {
        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console.log("ProxyAdmin:", address(proxyAdmin));

        // Transfer ownership
        proxyAdmin.transferOwnership(ANGLE_LABS);
        console.log("Transferred ProxyAdmin ownership to:", ANGLE_LABS);

        //vm.startBroadcast(DEPLOYER_ADDRESS);

        // Deploy implementation
        CoreBorrow implementation = new CoreBorrow();
        console.log("CoreBorrow Implementation:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(CoreBorrow.initialize, (ANGLE_LABS, DEPLOYER_ADDRESS));

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        // vm.stopBroadcast();

        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDistributor(address core) public returns (DeploymentAddresses memory) {
        //vm.startBroadcast(DEPLOYER_ADDRESS);

        // Deploy implementation
        Distributor implementation = new Distributor();
        console.log("Distributor Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("Distributor Proxy:", address(proxy));

        // Initialize
        Distributor(address(proxy)).initialize(ICore(core));

        // vm.stopBroadcast();

        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDistributionCreator(address core, address distributor) public returns (DeploymentAddresses memory) {
        //vm.startBroadcast(DEPLOYER_ADDRESS);

        // Deploy implementation
        DistributionCreator implementation = new DistributionCreator();
        console.log("DistributionCreator Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("DistributionCreator Proxy:", address(proxy));

        // Initialize
        DistributionCreator(address(proxy)).initialize(
            ICore(core),
            distributor,
            0.03 gwei // 0.03 gwei
        );

        // vm.stopBroadcast();

        return DeploymentAddresses(address(proxy), address(implementation));
    }
}
