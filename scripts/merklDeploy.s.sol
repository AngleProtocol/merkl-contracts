// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";

import { CreateXConstants } from "./utils/CreateXConstants.sol";
import { TokensUtils } from "./utils/TokensUtils.sol";

import { AccessControlManager } from "../contracts/AccessControlManager.sol";
import { Disputer } from "../contracts/Disputer.sol";
import { Distributor } from "../contracts/Distributor.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

// NOTE: Before running this script on a new chain, make sure to create the AngleLabs multisig and update the sdk with the new address
// Can be executed with (using zero address as default will fetch addresses from the sdk registry):
// forge script scripts/merklDeploy.s.sol \
//     --rpc-url $RPC_URL \
//     -vvvv
// Can be also be executed with (using zero address as default with addresses from the sdk registry):
// forge script scripts/merklDeploy.s.sol \
//     --sig "run(address,address)" \
//     "0x0000000000000000000000000000000000000000" "0x0000000000000000000000000000000000000000" \
//     --rpc-url $RPC_URL \
//     -vvvv
contract MainDeployScript is Script, TokensUtils, CreateXConstants {
    uint256 private DEPLOYER_PRIVATE_KEY;
    uint256 private MERKL_DEPLOYER_PRIVATE_KEY;

    // Constants and storage
    address public KEEPER = 0x435046800Fb9149eE65159721A92cB7d50a7534b;
    address public DUMPER = 0xeaC6A75e19beB1283352d24c0311De865a867DAB;
    address public TEMP_GOVERNOR = 0xb08AB4332AD871F89da24df4751968A61e58013c;
    address public GUARDIAN_ADDRESS = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701; // also deployer v2
    address public EXPECTED_MERKL_DEPLOYER_ADDRESS = 0x9f76a95AA7535bb0893cf88A146396e00ed21A12;

    address[] public DISPUTER_WHITELIST = [
        0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e,
        0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B,
        0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA
    ];

    uint256 public FUND_AMOUNT = 0.001 ether;

    address public ANGLE_LABS;
    address public DEPLOYER_ADDRESS;
    address public MERKL_DEPLOYER_ADDRESS;
    address public DISPUTE_TOKEN;

    struct DeploymentAddresses {
        address proxy;
        address implementation;
    }

    // NOTE: This function is used to automatically set the ANGLE_LABS and DISPUTE_TOKEN addresses from the sdk registry
    function run() external {
        DISPUTE_TOKEN = address(0);

        ANGLE_LABS = TEMP_GOVERNOR;

        _run(ANGLE_LABS, DISPUTE_TOKEN);
    }

    // NOTE: This function is used to manually set the ANGLE_LABS and DISPUTE_TOKEN addresses.
    // If angleLabs or disputeToken are set to the zero address, the script will try to fetch the addresses from the sdk registry
    function run(address angleLabs, address disputeToken) external {
        // Setup
        if (disputeToken != address(0)) {
            DISPUTE_TOKEN = disputeToken;
        } else {
            DISPUTE_TOKEN = address(0);
        }

        if (angleLabs != address(0)) {
            ANGLE_LABS = angleLabs;
        } else {
            ANGLE_LABS = TEMP_GOVERNOR;
        }

        _run(ANGLE_LABS, DISPUTE_TOKEN);
    }

    function _run(address angleLabs, address disputeToken) internal {
        ANGLE_LABS = angleLabs;
        DISPUTE_TOKEN = disputeToken;

        DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        MERKL_DEPLOYER_PRIVATE_KEY = vm.envUint("MERKL_DEPLOYER_PRIVATE_KEY");

        console.log("Chain ID:", block.chainid);
        console.log("ANGLE_LABS:", ANGLE_LABS);

        // Compute addresses from private keys
        DEPLOYER_ADDRESS = vm.addr(DEPLOYER_PRIVATE_KEY);
        MERKL_DEPLOYER_ADDRESS = vm.addr(MERKL_DEPLOYER_PRIVATE_KEY);
        console.log("DEPLOYER_ADDRESS:", DEPLOYER_ADDRESS);
        console.log("MERKL_DEPLOYER_ADDRESS:", MERKL_DEPLOYER_ADDRESS);
        console.log("DISPUTE TOKEN:", DISPUTE_TOKEN);

        if (DEPLOYER_ADDRESS == ANGLE_LABS) revert("ANGLE_LABS cannot be the deployer address");
        if (DEPLOYER_ADDRESS == EXPECTED_MERKL_DEPLOYER_ADDRESS) revert("DEPLOYER_ADDRESS cannot be the merkl deployer address"); // prevent from using the merkl deployer private key as deployer private key
        if (MERKL_DEPLOYER_ADDRESS != EXPECTED_MERKL_DEPLOYER_ADDRESS)
            revert("MERKL_DEPLOYER_ADDRESS is not the expected merkl deployer address"); // guarantee that MERKL_DEPLOYER_ADDRESS is the merkl deployer address

        // 1. Deploy using DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Transfer initial funds to required addresses
        transferInitialFunds();

        // Deploy ProxyAdmin
        address proxyAdmin = deployProxyAdmin();
        // Deploy AccessControlManager
        DeploymentAddresses memory accessControlManager = deployAccessControl(proxyAdmin);
        // Deploy AglaMerkl
        address aglaMerkl = deployAglaMerkl();

        vm.stopBroadcast();

        // 2. Deploy using MERKL_DEPLOYER_PRIVATE_KEY
        vm.startBroadcast(MERKL_DEPLOYER_PRIVATE_KEY);

        verifyMerklNonces();

        // Deploy Distributor
        DeploymentAddresses memory distributor = deployDistributor(accessControlManager.proxy);
        // Deploy DistributionCreator
        DeploymentAddresses memory creator = deployDistributionCreator(accessControlManager.proxy, distributor.proxy);

        vm.stopBroadcast();

        // 3. Set params and deploy Disputer using DEPLOYER_PRIVATE_KEY (make sure that the deployer is the GUARDIAN_ADDRESS)
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Set params and transfer ownership
        setDistributionCreatorParams(address(creator.proxy), aglaMerkl, DUMPER);
        setDistributorParams(address(distributor.proxy), DISPUTE_TOKEN, KEEPER);

        // Deploy Disputer
        address disputer = deployDisputer(distributor.proxy);

        // Revoke GOVENOR from DEPLOYER_ADDRESS if deployer is GUARDIAN_ADDRESS (keeping GUARDIAN role), else revoke both roles by calling removeGovernor
        if (DEPLOYER_ADDRESS == GUARDIAN_ADDRESS) {
            if (
                AccessControlManager(accessControlManager.proxy).getRoleMemberCount(
                    AccessControlManager(accessControlManager.proxy).GOVERNOR_ROLE()
                ) > 1
            ) {
                AccessControlManager(accessControlManager.proxy).revokeRole(
                    AccessControlManager(accessControlManager.proxy).GOVERNOR_ROLE(),
                    DEPLOYER_ADDRESS
                );
            } else {
                console.log("No governor to revoke, there must have been an error in the deployment");
            }
        } else {
            // removeGovernor already checks that there is at least one governor
            AccessControlManager(accessControlManager.proxy).removeGovernor(DEPLOYER_ADDRESS);
        }

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== Deployment Summary ===");
        console.log("ProxyAdmin:");
        console.log("  - Address:", proxyAdmin);
        console.log("AccessControlManager:");
        console.log("  - Proxy:", accessControlManager.proxy);
        console.log("  - Implementation:", accessControlManager.implementation);
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

    function deployAccessControl(address proxyAdmin) public returns (DeploymentAddresses memory) {
        console.log("\n=== Deploying AccessControlManager ===");

        // Deploy implementation
        AccessControlManager implementation = new AccessControlManager();
        console.log("AccessControlManager Implementation:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(AccessControlManager.initialize, (DEPLOYER_ADDRESS, ANGLE_LABS));

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);
        console.log("AccessControlManager Proxy:", address(proxy));

        AccessControlManager(address(proxy)).addGovernor(ANGLE_LABS);
        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDistributor(address accessControlManager) public returns (DeploymentAddresses memory) {
        console.log("\n=== Deploying Distributor ===");

        // Deploy implementation
        Distributor implementation = new Distributor();
        console.log("Distributor Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("Distributor Proxy:", address(proxy));

        // Initialize
        Distributor(address(proxy)).initialize(IAccessControlManager(accessControlManager));

        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDistributionCreator(address accessControlManager, address distributor) public returns (DeploymentAddresses memory) {
        console.log("\n=== Deploying DistributionCreator ===");

        // Deploy implementation
        DistributionCreator implementation = new DistributionCreator();
        console.log("DistributionCreator Implementation:", address(implementation));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        console.log("DistributionCreator Proxy:", address(proxy));

        // Initialize
        DistributionCreator(address(proxy)).initialize(
            IAccessControlManager(accessControlManager),
            distributor,
            0.03 gwei // 0.03 gwei
        );

        return DeploymentAddresses(address(proxy), address(implementation));
    }

    function deployDisputer(address distributor) public returns (address) {
        console.log("\n=== Deploying Disputer ===");

        bytes32 salt = vm.envBytes32("DEPLOY_SALT");

        // Check if deployer is the guardian
        if (DEPLOYER_ADDRESS != GUARDIAN_ADDRESS) {
            console.log("Skipping Disputer deployment - deployer is not the guardian");
            return address(0);
        }

        // Check if dispute token is set
        if (address(Distributor(distributor).disputeToken()) == address(0)) {
            console.log("Skipping Disputer deployment - dispute token not set");
            return address(0);
        }

        // Check if CREATEX contract is deployed
        address disputer;
        if (CREATEX.code.length == 0) {
            address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
            if (CREATE2_DEPLOYER.code.length != 0) {
                // Deploy using the standard Deterministic CREATE2 deployer and a deterministic salt
                disputer = address(new Disputer{ salt: salt }(DEPLOYER_ADDRESS, DISPUTER_WHITELIST, Distributor(distributor)));
            } else {
                // Classic deployment if CREATE2 deployer is not deployed
                disputer = address(new Disputer(DEPLOYER_ADDRESS, DISPUTER_WHITELIST, Distributor(distributor)));
            }
        } else {
            // Deploy using CreateX
            // Create initialization bytecode
            bytes
                memory bytecode = hex"60806040523480156200001157600080fd5b506040516200137738038062001377833981016040819052620000349162000322565b6200003f33620001b3565b600180546001600160a01b0319166001600160a01b0383169081179091556040805163c748d26160e01b8152905163c748d261916004808201926020929091908290030181865afa15801562000099573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620000bf91906200041f565b60405163095ea7b360e01b81526001600160a01b0383811660048301526000196024830152919091169063095ea7b3906044016020604051808303816000875af115801562000112573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000138919062000446565b50815160005b818110156200019d576001600260008684815181106200016257620001626200046a565b6020908102919091018101516001600160a01b03168252810191909152604001600020805460ff19169115159190911790556001016200013e565b50620001a98462000203565b5050505062000480565b600080546001600160a01b038381166001600160a01b0319831681178455604051919092169283917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e09190a35050565b6200020d62000286565b6001600160a01b038116620002785760405162461bcd60e51b815260206004820152602660248201527f4f776e61626c653a206e6577206f776e657220697320746865207a65726f206160448201526564647265737360d01b60648201526084015b60405180910390fd5b6200028381620001b3565b50565b6000546001600160a01b03163314620002e25760405162461bcd60e51b815260206004820181905260248201527f4f776e61626c653a2063616c6c6572206973206e6f7420746865206f776e657260448201526064016200026f565b565b6001600160a01b03811681146200028357600080fd5b80516200030781620002e4565b919050565b634e487b7160e01b600052604160045260246000fd5b6000806000606084860312156200033857600080fd5b83516200034581620002e4565b602085810151919450906001600160401b03808211156200036557600080fd5b818701915087601f8301126200037a57600080fd5b8151818111156200038f576200038f6200030c565b8060051b604051601f19603f83011681018181108582111715620003b757620003b76200030c565b60405291825284820192508381018501918a831115620003d657600080fd5b938501935b82851015620003ff57620003ef85620002fa565b84529385019392850192620003db565b8097505050505050506200041660408501620002fa565b90509250925092565b6000602082840312156200043257600080fd5b81516200043f81620002e4565b9392505050565b6000602082840312156200045957600080fd5b815180151581146200043f57600080fd5b634e487b7160e01b600052603260045260246000fd5b610ee780620004906000396000f3fe608060405234801561001057600080fd5b50600436106100c95760003560e01c80639b19251a11610081578063ca85e5d01161005b578063ca85e5d0146101bb578063e43252d7146101ce578063f2fde38b146101e157600080fd5b80639b19251a14610155578063bfe1092814610188578063c1075329146101a857600080fd5b806375619ab5116100b257806375619ab5146100eb5780638ab1d681146100fe5780638da5cb5b1461011157600080fd5b80631c20fadd146100ce578063715018a6146100e3575b600080fd5b6100e16100dc366004610c1d565b6101f4565b005b6100e161029b565b6100e16100f9366004610c5e565b6102af565b6100e161010c366004610c5e565b61055e565b60005473ffffffffffffffffffffffffffffffffffffffff165b60405173ffffffffffffffffffffffffffffffffffffffff90911681526020015b60405180910390f35b610178610163366004610c5e565b60026020526000908152604090205460ff1681565b604051901515815260200161014c565b60015461012b9073ffffffffffffffffffffffffffffffffffffffff1681565b6100e16101b6366004610c82565b6105b2565b6100e16101c9366004610cdd565b610659565b6100e16101dc366004610c5e565b6109f2565b6100e16101ef366004610c5e565b610a49565b6101fc610b05565b6040517fa9059cbb00000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff83811660048301526024820183905284169063a9059cbb906044016020604051808303816000875af1158015610271573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102959190610dac565b50505050565b6102a3610b05565b6102ad6000610b86565b565b6102b7610b05565b600160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663c748d2616040518163ffffffff1660e01b8152600401602060405180830381865afa158015610324573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906103489190610dce565b6001546040517f095ea7b300000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff91821660048201526000602482015291169063095ea7b3906044016020604051808303816000875af11580156103c0573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906103e49190610dac565b50600180547fffffffffffffffffffffffff00000000000000000000000000000000000000001673ffffffffffffffffffffffffffffffffffffffff8316908117909155604080517fc748d261000000000000000000000000000000000000000000000000000000008152905163c748d261916004808201926020929091908290030181865afa15801561047c573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906104a09190610dce565b6040517f095ea7b300000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff83811660048301527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6024830152919091169063095ea7b3906044016020604051808303816000875af1158015610536573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061055a9190610dac565b5050565b610566610b05565b73ffffffffffffffffffffffffffffffffffffffff16600090815260026020526040902080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00169055565b6105ba610b05565b60008273ffffffffffffffffffffffffffffffffffffffff168260405160006040518083038185875af1925050503d8060008114610614576040519150601f19603f3d011682016040523d82523d6000602084013e610619565b606091505b5050905080610654576040517f27fcd9d100000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b505050565b3360009081526002602052604090205460ff166106a2576040517f584a793800000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b600154604080517fc748d261000000000000000000000000000000000000000000000000000000008152905160009273ffffffffffffffffffffffffffffffffffffffff169163c748d2619160048083019260209291908290030181865afa158015610712573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906107369190610dce565b90506000600160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff166309454ba36040518163ffffffff1660e01b8152600401602060405180830381865afa1580156107a7573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906107cb9190610deb565b6040517f70a0823100000000000000000000000000000000000000000000000000000000815230600482015290915060009073ffffffffffffffffffffffffffffffffffffffff8416906370a0823190602401602060405180830381865afa15801561083b573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061085f9190610deb565b9050818110156109645773ffffffffffffffffffffffffffffffffffffffff83166323b872dd33306108918587610e04565b6040517fffffffff0000000000000000000000000000000000000000000000000000000060e086901b16815273ffffffffffffffffffffffffffffffffffffffff938416600482015292909116602483015260448201526064016020604051808303816000875af115801561090a573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061092e9190610dac565b610964576040517fb1eb39bb00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b6001546040517f2a25dd4100000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff90911690632a25dd41906109ba908790600401610e44565b600060405180830381600087803b1580156109d457600080fd5b505af11580156109e8573d6000803e3d6000fd5b5050505050505050565b6109fa610b05565b73ffffffffffffffffffffffffffffffffffffffff16600090815260026020526040902080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00166001179055565b610a51610b05565b73ffffffffffffffffffffffffffffffffffffffff8116610af9576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602660248201527f4f776e61626c653a206e6577206f776e657220697320746865207a65726f206160448201527f646472657373000000000000000000000000000000000000000000000000000060648201526084015b60405180910390fd5b610b0281610b86565b50565b60005473ffffffffffffffffffffffffffffffffffffffff1633146102ad576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820181905260248201527f4f776e61626c653a2063616c6c6572206973206e6f7420746865206f776e65726044820152606401610af0565b6000805473ffffffffffffffffffffffffffffffffffffffff8381167fffffffffffffffffffffffff0000000000000000000000000000000000000000831681178455604051919092169283917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e09190a35050565b73ffffffffffffffffffffffffffffffffffffffff81168114610b0257600080fd5b600080600060608486031215610c3257600080fd5b8335610c3d81610bfb565b92506020840135610c4d81610bfb565b929592945050506040919091013590565b600060208284031215610c7057600080fd5b8135610c7b81610bfb565b9392505050565b60008060408385031215610c9557600080fd5b8235610ca081610bfb565b946020939093013593505050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fd5b600060208284031215610cef57600080fd5b813567ffffffffffffffff80821115610d0757600080fd5b818401915084601f830112610d1b57600080fd5b813581811115610d2d57610d2d610cae565b604051601f82017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0908116603f01168101908382118183101715610d7357610d73610cae565b81604052828152876020848701011115610d8c57600080fd5b826020860160208301376000928101602001929092525095945050505050565b600060208284031215610dbe57600080fd5b81518015158114610c7b57600080fd5b600060208284031215610de057600080fd5b8151610c7b81610bfb565b600060208284031215610dfd57600080fd5b5051919050565b81810381811115610e3e577f4e487b7100000000000000000000000000000000000000000000000000000000600052601160045260246000fd5b92915050565b60006020808352835180602085015260005b81811015610e7257858101830151858201604001528201610e56565b5060006040828601015260407fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0601f830116850101925050509291505056fea26469706673582212202c48aee5de4959ef518786fa36afffd4b4a0c2f4af9e25741d18037fdf60170b64736f6c63430008180033000000000000000000000000a9ddd91249dfdd450e81e1c56ab60e1a6265170100000000000000000000000000000000000000000000000000000000000000600000000000000000000000003ef3d8ba38ebe18db133cec108f4d14ce00dd9ae0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ea05f9001fbdea6d4280879f283ff9d0b282060e0000000000000000000000000dd2ea40a3561c309c03b96108e78d06e8a1a99b000000000000000000000000f4c94b2fdc2efa4ad4b831f312e7ef74890705da";

            // Deploy using the specified CREATE2 deployer and a deterministic salt
            bytes memory callData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, bytecode);
            (bool success, bytes memory returnData) = CREATEX.call(callData);

            require(success, "CREATE2 deployment failed");
            disputer = address(uint160(uint256(bytes32(returnData))));
        }

        console.log("Disputer:", disputer);

        // Transfer ownership to AngleLabs
        console.log("Transferred Disputer ownership to AngleLabs:", ANGLE_LABS);
        Disputer(disputer).transferOwnership(ANGLE_LABS);

        // Send dispute tokens to disputer
        uint256 amount = 200 * 10 ** MockToken(DISPUTE_TOKEN).decimals();
        if (MockToken(DISPUTE_TOKEN).balanceOf(DEPLOYER_ADDRESS) >= amount) {
            transferERC20Tokens(disputer, 200 * 10 ** MockToken(DISPUTE_TOKEN).decimals(), DISPUTE_TOKEN);
            console.log("Sent dispute tokens to disputer:", 200 * 10 ** MockToken(DISPUTE_TOKEN).decimals());
        }

        return address(disputer);
    }

    function deployAglaMerkl() public returns (address) {
        console.log("\n=== Deploying AglaMerkl ===");

        // Deploy MockToken
        MockToken token = new MockToken("aglaMerkl", "aglaMerkl", 6);

        console.log("AglaMerkl Token:", address(token));
        console.log("Minting tokens to deployer:", DEPLOYER_ADDRESS);
        // Mint tokens to deployer
        token.mint(DEPLOYER_ADDRESS, 1_000_000_000_000_000_000_000_000_000);

        return address(token);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function setDistributionCreatorParams(address _distributionCreator, address aglaMerkl, address dumper) public {
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
        console.log("Setting dumper as fee recipient:", dumper);
        distributionCreator.setFeeRecipient(dumper);

        // Set campaign fees to 5% for airdrop campaigns
        console.log("Setting campaign fees to 5% for airdrop campaigns");
        distributionCreator.setCampaignFees(4, 5 * 1e6);

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

        // Set dispute amount to 100 tokens (18 decimals)
        string memory symbol = MockToken(disputeToken).symbol();
        uint8 decimals = MockToken(disputeToken).decimals();
        console.log("Token decimals:", decimals);
        if (
            keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("EURA")) ||
            keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("USDC")) ||
            keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("USDT"))
        ) {
            console.log("Setting dispute amount to 100", symbol);
            distributor.setDisputeAmount(100 * 10 ** decimals);
        }
        if (keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("WETH"))) {
            console.log("Setting dispute amount to 0.03", symbol);
            distributor.setDisputeAmount(3 * 10 ** (decimals - 2));
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function verifyMerklNonces() public view {
        address EXPECTED_DISTRIBUTOR_IMPLEMENTATION_ADDRESS = 0x918261fa5Dd9C3b1358cA911792E9bDF3c5CCa35;
        address EXPECTED_DISTRIBUTOR_PROXY_ADDRESS = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
        address EXPECTED_DISTRIBUTION_CREATOR_IMPLEMENTATION_ADDRESS = 0x7Db28175B63f154587BbB1Cae62D39Ea80A23383;
        address EXPECTED_DISTRIBUTION_CREATOR_PROXY_ADDRESS = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;

        // deploy DISTRIBUTOR implementation nonce 0
        // deploy DISTRIBUTOR proxy nonce 1
        // initialize DISTRIBUTOR nonce 2
        // deploy DISTRIBUTION_CREATOR implementation nonce 3
        // deploy DISTRIBUTION_CREATOR proxy nonce 4
        // initialize DISTRIBUTION_CREATOR nonce 5
        if (EXPECTED_DISTRIBUTOR_IMPLEMENTATION_ADDRESS != vm.computeCreateAddress(MERKL_DEPLOYER_ADDRESS, 0))
            revert("DISTRIBUTOR_IMPLEMENTATION_ADDRESS_MISMATCH");
        if (EXPECTED_DISTRIBUTOR_PROXY_ADDRESS != vm.computeCreateAddress(MERKL_DEPLOYER_ADDRESS, 1))
            revert("DISTRIBUTOR_PROXY_ADDRESS_MISMATCH");
        if (EXPECTED_DISTRIBUTION_CREATOR_IMPLEMENTATION_ADDRESS != vm.computeCreateAddress(MERKL_DEPLOYER_ADDRESS, 3))
            revert("DISTRIBUTION_CREATOR_IMPLEMENTATION_ADDRESS_MISMATCH");
        if (EXPECTED_DISTRIBUTION_CREATOR_PROXY_ADDRESS != vm.computeCreateAddress(MERKL_DEPLOYER_ADDRESS, 4))
            revert("DISTRIBUTION_CREATOR_PROXY_ADDRESS_MISMATCH");
    }

    function transferInitialFunds() internal {
        console.log("\n=== Transferring initial funds ===");

        // Calculate total recipients including KEEPER, DUMPER, DISPUTER_WHITELIST
        uint256 transferLength = 3 + DISPUTER_WHITELIST.length;

        // Check deployer balance
        if (DEPLOYER_ADDRESS.balance < FUND_AMOUNT * transferLength) {
            revert(
                "DEPLOYER_ADDRESS does not have enough balance to transfer to KEEPER, DUMPER and DISPUTER_WHITELIST, please fund the deployer and check FUND_AMOUNT if needed"
            );
        }

        // Prepare recipient and amount arrays
        address[] memory recipients = new address[](transferLength);
        uint256[] memory amounts = new uint256[](transferLength);

        // Add KEEPER, DUMPER and MERKL_DEPLOYER_ADDRESS
        recipients[0] = KEEPER;
        recipients[1] = DUMPER;
        recipients[2] = MERKL_DEPLOYER_ADDRESS;
        amounts[0] = FUND_AMOUNT;
        amounts[1] = FUND_AMOUNT;
        amounts[2] = FUND_AMOUNT;

        // Add DISPUTER_WHITELIST
        for (uint256 i = 0; i < DISPUTER_WHITELIST.length; i++) {
            recipients[i + 3] = DISPUTER_WHITELIST[i];
            amounts[i + 3] = FUND_AMOUNT;
        }

        console.log("Transferring funds to required addresses:", FUND_AMOUNT);
        console.log("Total amount transferred:", FUND_AMOUNT * transferLength);
        transferNativeTokens(recipients, amounts);
    }
}
