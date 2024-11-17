// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CoreBorrow } from "../../contracts/core/CoreBorrow.sol";
import { Disputer } from "../../contracts/Disputer.sol";
import { Distributor } from "../../contracts/Distributor.sol";
import { DistributionCreator } from "../../contracts/DistributionCreator.sol";
import { console } from "forge-std/console.sol";
import { JsonReader } from "../utils/JsonReader.sol";
import { ICore } from "../../contracts/interfaces/ICore.sol";
import { BaseScript } from "../utils/Base.s.sol";
import { MockToken } from "../../contracts/mock/MockToken.sol";

contract MainDeployScript is Script, BaseScript {
    uint256 private DEPLOYER_PRIVATE_KEY;
    uint256 private MERKL_DEPLOYER_PRIVATE_KEY;

    // Constants and storage
    address public GUARDIAN_ADDRESS = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
    address public ANGLE_LABS;
    address public DEPLOYER_ADDRESS;
    address public MERKL_DEPLOYER_ADDRESS;
    address public EURA;

    JsonReader public reader;

    struct DeploymentAddresses {
        address proxy;
        address implementation;
    }

    function run() external {
        // Setup
        DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        MERKL_DEPLOYER_PRIVATE_KEY = vm.envUint("MERKL_DEPLOYER_PRIVATE_KEY");
        reader = new JsonReader();
        console.log("Chain ID:", block.chainid);

        try reader.readAddress(block.chainid, "EUR.AgToken") returns (address eura) {
            EURA = eura;
        } catch {
            EURA = address(0);
        }

        ANGLE_LABS = reader.readAddress(block.chainid, "AngleLabs");
        console.log("ANGLE_LABS:", ANGLE_LABS);

        // Compute addresses from private keys
        // DEPLOYER_ADDRESS = vm.addr(DEPLOYER_PRIVATE_KEY);
        DEPLOYER_ADDRESS = vm.addr(DEPLOYER_PRIVATE_KEY);
        MERKL_DEPLOYER_ADDRESS = vm.addr(MERKL_DEPLOYER_PRIVATE_KEY);
        console.log("DEPLOYER_ADDRESS:", DEPLOYER_ADDRESS);
        console.log("MERKL_DEPLOYER_ADDRESS:", MERKL_DEPLOYER_ADDRESS);
        console.log("EURA:", EURA);

        // 1. Deploy using DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy ProxyAdmin
        address proxyAdmin = deployProxyAdmin();
        // Deploy CoreBorrow
        DeploymentAddresses memory coreBorrow = deployCoreBorrow(proxyAdmin);

        vm.stopBroadcast();

        // 2. Deploy using MERKL_DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(MERKL_DEPLOYER_PRIVATE_KEY);

        // Deploy Distributor
        DeploymentAddresses memory distributor = deployDistributor(coreBorrow.proxy);
        // Deploy DistributionCreator
        DeploymentAddresses memory creator = deployDistributionCreator(coreBorrow.proxy, distributor.proxy);

        vm.stopBroadcast();

        // 3. Deploy using DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy Disputer
        // First, set dispute token if EURA is set
        if (EURA != address(0)) Distributor(distributor.proxy).setDisputeToken(IERC20(EURA));
        // Then deploy Disputer
        address disputer = deployDisputer(distributor.proxy);

        // Deploy AglaMerkl
        address aglaMerkl = deployAglaMerkl();

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== Deployment Summary ===");
        console.log("ProxyAdmin:");
        console.log("  - Address:", proxyAdmin);
        console.log("CoreBorrow:");
        console.log("  - Proxy:", coreBorrow.proxy);
        console.log("  - Implementation:", coreBorrow.implementation);
        console.log("Distributor:");
        console.log("  - Proxy:", distributor.proxy);
        console.log("  - Implementation:", distributor.implementation);
        console.log("DistributionCreator:");
        console.log("  - Proxy:", creator.proxy);
        console.log("  - Implementation:", creator.implementation);
        if (disputer != address(0)) {
            console.log("Disputer:");
            console.log("  - Address:", disputer);
        }
        console.log("AglaMerkl:");
        console.log("  - Address:", aglaMerkl);

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

    function deployProxyAdmin() public returns (address) {
        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console.log("ProxyAdmin:", address(proxyAdmin));

        // Transfer ownership
        proxyAdmin.transferOwnership(ANGLE_LABS);
        console.log("Transferred ProxyAdmin ownership to:", ANGLE_LABS);

        return address(proxyAdmin);
    }

    function deployCoreBorrow(address proxyAdmin) public returns (DeploymentAddresses memory) {
        console.log("\n=== Deploying CoreBorrow ===");

        // Deploy implementation
        CoreBorrow implementation = new CoreBorrow();
        console.log("CoreBorrow Implementation:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(CoreBorrow.initialize, (DEPLOYER_ADDRESS, GUARDIAN_ADDRESS));

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        console.log("CoreBorrow Proxy:", address(proxy));

        CoreBorrow(address(proxy)).addGovernor(ANGLE_LABS);
        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDistributor(address core) public returns (DeploymentAddresses memory) {
        console.log("\n=== Deploying Distributor ===");

        // Deploy implementation
        Distributor implementation = new Distributor();
        console.log("Distributor Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("Distributor Proxy:", address(proxy));

        // Initialize
        Distributor(address(proxy)).initialize(ICore(core));

        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDistributionCreator(address core, address distributor) public returns (DeploymentAddresses memory) {
        console.log("\n=== Deploying DistributionCreator ===");

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

        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDisputer(address distributor) public returns (address) {
        console.log("\n=== Deploying Disputer ===");

        // Check if dispute token is set
        if (address(Distributor(distributor).disputeToken()) == address(0)) {
            console.log("Skipping Disputer deployment - dispute token not set");
            return address(0);
        }
        // Deploy implementation directly (no proxy needed)
        address[] memory whitelist = new address[](3);
        whitelist[0] = 0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e;
        whitelist[1] = 0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B;
        whitelist[2] = 0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA;

        // Disputer disputer = new Disputer(DEPLOYER_ADDRESS, whitelist, Distributor(distributor));

        // Create initialization bytecode
        bytes memory bytecode = abi.encodePacked(
            type(Disputer).creationCode,
            abi.encode(DEPLOYER_ADDRESS, whitelist, Distributor(distributor))
        );

        // Use a deterministic salt
        bytes32 salt = vm.envBytes32("DEPLOY_SALT");

        // Deploy using the specified CREATE2 deployer
        address createX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
        (bool success, bytes memory returnData) = createX.call(
            abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, bytecode)
        );

        require(success, "CREATE2 deployment failed");
        address disputer = address(uint160(uint256(bytes32(returnData))));

        console.log("Disputer:", disputer);
        return address(disputer);
    }

    function deployAglaMerkl() public returns (address) {
        console.log("\n=== Deploying AglaMerkl ===");

        // Deploy MockToken with same parameters as in TypeScript
        MockToken token = new MockToken("aglaMerkl", "aglaMerkl", 6);

        // Mint the same amount of tokens to the deployer
        token.mint(msg.sender, 1000000000000000000000000000);

        console.log("AglaMerkl Token:", address(token));
        return address(token);
    }
}
