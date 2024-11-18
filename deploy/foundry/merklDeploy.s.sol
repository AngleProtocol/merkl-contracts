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

// NOTE: Before running this script on a new chain, make sure to create the AngleLabs multisig and update the sdk with the new address
contract MainDeployScript is Script, BaseScript, JsonReader {
    uint256 private DEPLOYER_PRIVATE_KEY;
    uint256 private MERKL_DEPLOYER_PRIVATE_KEY;

    // Constants and storage
    address public KEEPER = 0x435046800Fb9149eE65159721A92cB7d50a7534b;
    address public GUARDIAN_ADDRESS = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
    address public ANGLE_LABS;
    address public DEPLOYER_ADDRESS;
    address public MERKL_DEPLOYER_ADDRESS;
    address public DISPUTE_TOKEN;

    JsonReader public reader;

    struct DeploymentAddresses {
        address proxy;
        address implementation;
    }

    function run() external {
        // Setup
        DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        MERKL_DEPLOYER_PRIVATE_KEY = vm.envUint("MERKL_DEPLOYER_PRIVATE_KEY");
        console.log("Chain ID:", block.chainid);

        try this.readAddress(block.chainid, "EUR.AgToken") returns (address eura) {
            DISPUTE_TOKEN = eura;
        } catch {
            DISPUTE_TOKEN = address(0);
        }

        try this.readAddress(block.chainid, "AngleLabs") returns (address angleLabs) {
            ANGLE_LABS = angleLabs;
        } catch {
            ANGLE_LABS = GUARDIAN_ADDRESS;
        }
        console.log("ANGLE_LABS:", ANGLE_LABS);

        // Compute addresses from private keys
        // DEPLOYER_ADDRESS = vm.addr(DEPLOYER_PRIVATE_KEY);
        DEPLOYER_ADDRESS = vm.addr(DEPLOYER_PRIVATE_KEY);
        MERKL_DEPLOYER_ADDRESS = vm.addr(MERKL_DEPLOYER_PRIVATE_KEY);
        console.log("DEPLOYER_ADDRESS:", DEPLOYER_ADDRESS);
        console.log("MERKL_DEPLOYER_ADDRESS:", MERKL_DEPLOYER_ADDRESS);
        console.log("DISPUTE TOKEN (EURA):", DISPUTE_TOKEN);

        // 1. Deploy using DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy ProxyAdmin
        address proxyAdmin = deployProxyAdmin();
        // Deploy CoreBorrow
        DeploymentAddresses memory coreBorrow = deployCoreBorrow(proxyAdmin);
        // Deploy AglaMerkl
        address aglaMerkl = deployAglaMerkl();

        vm.stopBroadcast();

        // 2. Deploy using MERKL_DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(MERKL_DEPLOYER_PRIVATE_KEY);

        // Deploy Distributor
        DeploymentAddresses memory distributor = deployDistributor(coreBorrow.proxy);
        // Deploy DistributionCreator
        DeploymentAddresses memory creator = deployDistributionCreator(coreBorrow.proxy, distributor.proxy);

        vm.stopBroadcast();

        // 3. Set params and deploy Disputer using DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Set params and transfer ownership
        setDistributionCreatorParams(address(creator.proxy), aglaMerkl, KEEPER);
        setDistributorParams(address(distributor.proxy), DISPUTE_TOKEN, KEEPER);

        // Deploy Disputer
        address disputer = deployDisputer(distributor.proxy);

        // Revoke GOVENOR from DEPLOYER_ADDRESS if deployer is GUARDIAN_ADDRESS, else revoke both roles by calling removeGovernor
        if (DEPLOYER_ADDRESS == GUARDIAN_ADDRESS) {
            CoreBorrow(coreBorrow.proxy).revokeRole(CoreBorrow(coreBorrow.proxy).GOVERNOR_ROLE(), DEPLOYER_ADDRESS);
        } else {
            CoreBorrow(coreBorrow.proxy).removeGovernor(DEPLOYER_ADDRESS);
        }

        console.log(CoreBorrow(coreBorrow.proxy).getRoleMemberCount(CoreBorrow(coreBorrow.proxy).GOVERNOR_ROLE()));
        console.log(CoreBorrow(coreBorrow.proxy).getRoleMemberCount(CoreBorrow(coreBorrow.proxy).GUARDIAN_ROLE()));
        console.log(CoreBorrow(coreBorrow.proxy).hasRole(CoreBorrow(coreBorrow.proxy).GOVERNOR_ROLE(), ANGLE_LABS));
        console.log(CoreBorrow(coreBorrow.proxy).hasRole(CoreBorrow(coreBorrow.proxy).GUARDIAN_ROLE(), ANGLE_LABS));

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
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   DEPLOY FUNCTIONS                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function deployProxyAdmin() public returns (address) {
        console.log("\n=== Deploying ProxyAdmin ===");

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

        // Transfer ownership to AngleLabs
        Disputer(disputer).transferOwnership(ANGLE_LABS);
        console.log("Transferred Disputer ownership to AngleLabs:", ANGLE_LABS);

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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function setDistributionCreatorParams(address _distributionCreator, address aglaMerkl, address keeper) public {
        console.log("\n=== Setting DistributionCreator params ===");

        DistributionCreator distributionCreator = DistributionCreator(_distributionCreator);

        // Set min amount to 1 for reward tokens
        uint256[] memory minAmounts = new uint256[](1);
        address[] memory tokens = new address[](1);
        minAmounts[0] = 1;
        tokens[0] = aglaMerkl;
        console.log("Setting reward token min amounts to 1 for:", aglaMerkl);
        distributionCreator.setRewardTokenMinAmounts(tokens, minAmounts);

        // Set keeper as fee recipient
        console.log("Setting keeper as fee recipient:", keeper);
        distributionCreator.setFeeRecipient(keeper);

        // Set message
        console.log("Setting message");
        distributionCreator.setMessage(
            " 1. Merkl is experimental software provided as is, use it at your own discretion. There may notably be delays in the onchain Merkle root updates and there may be flaws in the script (or engine) or in the infrastructure used to update results onchain. In that regard, everyone can permissionlessly dispute the rewards which are posted onchain, and when creating a distribution, you are responsible for checking the results and eventually dispute them. 2. If you are specifying an invalid pool address or a pool from an AMM that is not marked as supported, your rewards will not be taken into account and you will not be able to recover them. 3. If you do not blacklist liquidity position managers or smart contract addresses holding LP tokens that are not natively supported by the Merkl system, or if you don't specify the addresses of the liquidity position managers that are not automatically handled by the system, then the script will not be able to take the specifities of these addresses into account, and it will reward them like a normal externally owned account would be. If these are smart contracts that do not support external rewards, then rewards that should be accruing to it will be lost. 4. If rewards sent through Merkl remain unclaimed for a period of more than 1 year after the end of the distribution (because they are meant for instance for smart contract addresses that cannot claim or deal with them), then we reserve the right to recover these rewards. 5. Fees apply to incentives deposited on Merkl, unless the pools incentivized contain a whitelisted token (e.g an Angle Protocol stablecoin). 6. By interacting with the Merkl smart contract to deposit an incentive for a pool, you are exposed to smart contract risk and to the offchain mechanism used to compute reward distribution. 7. If the rewards you are sending are too small in value, or if you are sending rewards using a token that is not approved for it, your rewards will not be handled by the script, and they may be lost. 8. If you mistakenly send too much rewards compared with what you wanted to send, you will not be able to call them back. You will also not be able to prematurely end a reward distribution once created. 9. The engine handling reward distribution for a pool may not look at all the swaps occurring on the pool during the time for which you are incentivizing, but just at a subset of it to gain in efficiency. Overall, if you distribute incentives using Merkl, it means that you are aware of how the engine works, of the approximations it makes and of the behaviors it may trigger (e.g. just in time liquidity). 10. Rewards corresponding to incentives distributed through Merkl do not compound block by block, but are regularly made available (through a Merkle root update) at a frequency which depends on the chain. "
        );
    }

    function setDistributorParams(address _distributor, address disputeToken, address keeper) public {
        console.log("\n=== Setting Distributor params ===");
        Distributor distributor = Distributor(_distributor);

        // Toggle trusted status for keeper
        console.log("Toggling trusted status for keeper:", keeper);
        distributor.toggleTrusted(keeper);

        // Set dispute token (DISPUTE_TOKEN if available, skip otherwise)
        console.log("Setting dispute token:", disputeToken);
        if (disputeToken != address(0)) distributor.setDisputeToken(IERC20(disputeToken));

        // Set dispute period
        console.log("Setting dispute period to 1");
        distributor.setDisputePeriod(1);

        // Set dispute amount to 100 EURA (18 decimals)
        console.log("Setting dispute amount to 100 EURA (18 decimals)");
        distributor.setDisputeAmount(100 * 10 ** 18);
    }
}
