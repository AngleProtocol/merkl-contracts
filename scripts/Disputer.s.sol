// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./utils/Base.s.sol";
import { Disputer } from "../contracts/Disputer.sol";
import { Distributor } from "../contracts/Distributor.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";
import { TokensUtils } from "./utils/TokensUtils.sol";
import { CreateXConstants } from "./utils/CreateXConstants.sol";

// Base contract with shared constants and utilities
contract DisputerScript is BaseScript {
    address[] public DISPUTER_WHITELIST = [
        0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e,
        0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B,
        0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA
    ];
}

// Deploy scrip
contract Deploy is DisputerScript {
    function run() external broadcast {
        uint256 chainId = block.chainid;
        console.log("DEPLOYER_ADDRESS:", broadcaster);

        // Read configuration from JSON
        // TODO: replace
        address angleLabs = address(0);
        address distributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

        address disputer = address(
            new Disputer{ salt: vm.envBytes32("DEPLOY_SALT") }(broadcaster, DISPUTER_WHITELIST, Distributor(distributor))
        );
        Disputer(disputer).transferOwnership(angleLabs);

        console.log("Disputer deployed at:", disputer);
    }
}

// SetDistributor scrip
contract SetDistributor is DisputerScript {
    function run(Distributor newDistributor) external {
        _run(newDistributor);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET YOUR DESIRED DISTRIBUTOR ADDRESS
        address distributorAddress = address(0);
        _run(Distributor(distributorAddress));
    }

    function _run(Distributor _newDistributor) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address disputerAddress = address(0);

        Disputer(disputerAddress).setDistributor(_newDistributor);

        console.log("Distributor updated to:", address(_newDistributor));
    }
}

// AddToWhitelist scrip
contract AddToWhitelist is DisputerScript {
    function run(address account) external {
        _run(account);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE ACCOUNT TO WHITELIST
        address account = address(0);
        _run(account);
    }

    function _run(address _account) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address disputerAddress = address(0);

        Disputer(disputerAddress).addToWhitelist(_account);

        console.log("Address added to whitelist:", _account);
    }
}

// RemoveFromWhitelist scrip
contract RemoveFromWhitelist is DisputerScript {
    function run(address account) external {
        _run(account);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE ACCOUNT TO REMOVE FROM WHITELIST
        address accountToRemove = address(0);
        _run(accountToRemove);
    }

    function _run(address _account) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address disputerAddress = address(0);

        Disputer(disputerAddress).removeFromWhitelist(_account);
        console.log("Address removed from whitelist:", _account);
    }
}

// FundDisputerWhitelist script
contract FundDisputerWhitelist is DisputerScript {
    function run(uint256 amountToFund) external {
        _run(amountToFund);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE FUNDING AMOUNT (in ether)
        uint256 amountToFund = 0.001 ether;
        _run(amountToFund);
    }

    function _run(uint256 _amountToFund) internal broadcast {
        console.log("Chain ID:", block.chainid);

        // Fund each whitelisted address
        for (uint256 i = 0; i < DISPUTER_WHITELIST.length; i++) {
            address recipient = DISPUTER_WHITELIST[i];
            console.log("Funding whitelist address:", recipient);

            // Transfer native token
            (bool success, ) = recipient.call{ value: _amountToFund }("");
            require(success, "Transfer failed");

            console.log("Funded with amount:", _amountToFund);
        }

        // Print summary
        console.log("\n=== Funding Summary ===");
        console.log("Amount per address:", _amountToFund);
        console.log("Number of addresses funded:", DISPUTER_WHITELIST.length);
    }
}

contract FundDisputer is DisputerScript {
    function run(uint256 amountToFund) external {
        _run(amountToFund);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE FUNDING AMOUNT (in dispute tokens decimals)
        uint256 amountToFund = 100 * 10 ** 6; // i.e. 100 USDC -> 100 * 10 ** 6
        _run(amountToFund);
    }

    function _run(uint256 _amountToFund) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address disputerAddress = address(0);

        IERC20 disputeToken = Disputer(disputerAddress).distributor().disputeToken();
        console.log("Transferring %s to %s", _amountToFund, disputerAddress);
        disputeToken.transfer(disputerAddress, _amountToFund);
    }
}

contract WithdrawFunds is DisputerScript {
    function run() external {
        // MODIFY THESE VALUES TO SET THE WITHDRAWAL PARAMETERS
        address asset = address(0); // Use address(0) for ETH, or token address for ERC20
        uint256 amountToWithdraw = 100 * 10 ** 6; // Adjust decimals according to asset
        address recipient = address(0); // Set the recipient address
        _run(asset, recipient, amountToWithdraw);
    }

    function run(address asset, address recipient, uint256 amountToWithdraw) external {
        _run(asset, recipient, amountToWithdraw);
    }

    function _run(address asset, address to, uint256 _amountToWithdraw) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address disputerAddress = address(0);
        Disputer disputer = Disputer(disputerAddress);

        if (asset == address(0)) {
            // Withdraw ETH
            disputer.withdrawFunds(payable(to), _amountToWithdraw);
            console.log("Withdrew %s ETH to %s", _amountToWithdraw, to);
        } else {
            // Withdraw ERC20 token
            disputer.withdrawFunds(asset, to, _amountToWithdraw);
            console.log("Withdrew %s %s to %s", _amountToWithdraw, asset, to);
        }
    }
}

// ToggleDispute script
contract ToggleDispute is DisputerScript {
    function run(string memory reason) external {
        _run(reason);
    }

    function run() external {
        // MODIFY THIS VALUE TO SET THE DISPUTE REASON TO TOGGLE
        string memory reason = "test";
        _run(reason);
    }

    function _run(string memory _reason) internal broadcast {
        uint256 chainId = block.chainid;
        // TODO: replace
        address disputerAddress = address(0);
        Disputer(disputerAddress).toggleDispute(_reason);
        console.log("Toggled dispute for:", _reason);
    }
}

contract DeployWithCreate is DisputerScript, TokensUtils, CreateXConstants {
    function run(address disputeToken) external broadcast {
        uint256 chainId = block.chainid;
        address distributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

        deployDisputer(distributor, disputeToken);
    }

    function deployDisputer(address distributor, address disputeToken) public returns (address) {
        console.log("\n=== Deploying Disputer ===");

        bytes32 salt = vm.envBytes32("DEPLOY_SALT");

        // Check if CREATEX contract is deployed
        address disputer;
        // if (CREATEX.code.length == 0) {
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        // if (CREATE2_DEPLOYER.code.length != 0) {

        //     // Deploy using the standard Deterministic CREATE2 deployer and a deterministic salt
        //     disputer = address(new Disputer{ salt: salt }(broadcaster, DISPUTER_WHITELIST, Distributor(distributor)));
        // } else {
        //     // Classic deployment if CREATE2 deployer is not deployed
        //     // disputer = address(new Disputer(broadcaster, DISPUTER_WHITELIST, Distributor(distributor)));
        // }
        // } else {
        // Deploy using CreateX
        // Create initialization bytecode
        bytes
            memory bytecode = hex"60806040523480156200001157600080fd5b506040516200137738038062001377833981016040819052620000349162000322565b6200003f33620001b3565b600180546001600160a01b0319166001600160a01b0383169081179091556040805163c748d26160e01b8152905163c748d261916004808201926020929091908290030181865afa15801562000099573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620000bf91906200041f565b60405163095ea7b360e01b81526001600160a01b0383811660048301526000196024830152919091169063095ea7b3906044016020604051808303816000875af115801562000112573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000138919062000446565b50815160005b818110156200019d576001600260008684815181106200016257620001626200046a565b6020908102919091018101516001600160a01b03168252810191909152604001600020805460ff19169115159190911790556001016200013e565b50620001a98462000203565b5050505062000480565b600080546001600160a01b038381166001600160a01b0319831681178455604051919092169283917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e09190a35050565b6200020d62000286565b6001600160a01b038116620002785760405162461bcd60e51b815260206004820152602660248201527f4f776e61626c653a206e6577206f776e657220697320746865207a65726f206160448201526564647265737360d01b60648201526084015b60405180910390fd5b6200028381620001b3565b50565b6000546001600160a01b03163314620002e25760405162461bcd60e51b815260206004820181905260248201527f4f776e61626c653a2063616c6c6572206973206e6f7420746865206f776e657260448201526064016200026f565b565b6001600160a01b03811681146200028357600080fd5b80516200030781620002e4565b919050565b634e487b7160e01b600052604160045260246000fd5b6000806000606084860312156200033857600080fd5b83516200034581620002e4565b602085810151919450906001600160401b03808211156200036557600080fd5b818701915087601f8301126200037a57600080fd5b8151818111156200038f576200038f6200030c565b8060051b604051601f19603f83011681018181108582111715620003b757620003b76200030c565b60405291825284820192508381018501918a831115620003d657600080fd5b938501935b82851015620003ff57620003ef85620002fa565b84529385019392850192620003db565b8097505050505050506200041660408501620002fa565b90509250925092565b6000602082840312156200043257600080fd5b81516200043f81620002e4565b9392505050565b6000602082840312156200045957600080fd5b815180151581146200043f57600080fd5b634e487b7160e01b600052603260045260246000fd5b610ee780620004906000396000f3fe608060405234801561001057600080fd5b50600436106100c95760003560e01c80639b19251a11610081578063ca85e5d01161005b578063ca85e5d0146101bb578063e43252d7146101ce578063f2fde38b146101e157600080fd5b80639b19251a14610155578063bfe1092814610188578063c1075329146101a857600080fd5b806375619ab5116100b257806375619ab5146100eb5780638ab1d681146100fe5780638da5cb5b1461011157600080fd5b80631c20fadd146100ce578063715018a6146100e3575b600080fd5b6100e16100dc366004610c1d565b6101f4565b005b6100e161029b565b6100e16100f9366004610c5e565b6102af565b6100e161010c366004610c5e565b61055e565b60005473ffffffffffffffffffffffffffffffffffffffff165b60405173ffffffffffffffffffffffffffffffffffffffff90911681526020015b60405180910390f35b610178610163366004610c5e565b60026020526000908152604090205460ff1681565b604051901515815260200161014c565b60015461012b9073ffffffffffffffffffffffffffffffffffffffff1681565b6100e16101b6366004610c82565b6105b2565b6100e16101c9366004610cdd565b610659565b6100e16101dc366004610c5e565b6109f2565b6100e16101ef366004610c5e565b610a49565b6101fc610b05565b6040517fa9059cbb00000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff83811660048301526024820183905284169063a9059cbb906044016020604051808303816000875af1158015610271573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102959190610dac565b50505050565b6102a3610b05565b6102ad6000610b86565b565b6102b7610b05565b600160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663c748d2616040518163ffffffff1660e01b8152600401602060405180830381865afa158015610324573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906103489190610dce565b6001546040517f095ea7b300000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff91821660048201526000602482015291169063095ea7b3906044016020604051808303816000875af11580156103c0573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906103e49190610dac565b50600180547fffffffffffffffffffffffff00000000000000000000000000000000000000001673ffffffffffffffffffffffffffffffffffffffff8316908117909155604080517fc748d261000000000000000000000000000000000000000000000000000000008152905163c748d261916004808201926020929091908290030181865afa15801561047c573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906104a09190610dce565b6040517f095ea7b300000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff83811660048301527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6024830152919091169063095ea7b3906044016020604051808303816000875af1158015610536573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061055a9190610dac565b5050565b610566610b05565b73ffffffffffffffffffffffffffffffffffffffff16600090815260026020526040902080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00169055565b6105ba610b05565b60008273ffffffffffffffffffffffffffffffffffffffff168260405160006040518083038185875af1925050503d8060008114610614576040519150601f19603f3d011682016040523d82523d6000602084013e610619565b606091505b5050905080610654576040517f27fcd9d100000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b505050565b3360009081526002602052604090205460ff166106a2576040517f584a793800000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b600154604080517fc748d261000000000000000000000000000000000000000000000000000000008152905160009273ffffffffffffffffffffffffffffffffffffffff169163c748d2619160048083019260209291908290030181865afa158015610712573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906107369190610dce565b90506000600160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff166309454ba36040518163ffffffff1660e01b8152600401602060405180830381865afa1580156107a7573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906107cb9190610deb565b6040517f70a0823100000000000000000000000000000000000000000000000000000000815230600482015290915060009073ffffffffffffffffffffffffffffffffffffffff8416906370a0823190602401602060405180830381865afa15801561083b573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061085f9190610deb565b9050818110156109645773ffffffffffffffffffffffffffffffffffffffff83166323b872dd33306108918587610e04565b6040517fffffffff0000000000000000000000000000000000000000000000000000000060e086901b16815273ffffffffffffffffffffffffffffffffffffffff938416600482015292909116602483015260448201526064016020604051808303816000875af115801561090a573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061092e9190610dac565b610964576040517fb1eb39bb00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b6001546040517f2a25dd4100000000000000000000000000000000000000000000000000000000815273ffffffffffffffffffffffffffffffffffffffff90911690632a25dd41906109ba908790600401610e44565b600060405180830381600087803b1580156109d457600080fd5b505af11580156109e8573d6000803e3d6000fd5b5050505050505050565b6109fa610b05565b73ffffffffffffffffffffffffffffffffffffffff16600090815260026020526040902080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00166001179055565b610a51610b05565b73ffffffffffffffffffffffffffffffffffffffff8116610af9576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602660248201527f4f776e61626c653a206e6577206f776e657220697320746865207a65726f206160448201527f646472657373000000000000000000000000000000000000000000000000000060648201526084015b60405180910390fd5b610b0281610b86565b50565b60005473ffffffffffffffffffffffffffffffffffffffff1633146102ad576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820181905260248201527f4f776e61626c653a2063616c6c6572206973206e6f7420746865206f776e65726044820152606401610af0565b6000805473ffffffffffffffffffffffffffffffffffffffff8381167fffffffffffffffffffffffff0000000000000000000000000000000000000000831681178455604051919092169283917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e09190a35050565b73ffffffffffffffffffffffffffffffffffffffff81168114610b0257600080fd5b600080600060608486031215610c3257600080fd5b8335610c3d81610bfb565b92506020840135610c4d81610bfb565b929592945050506040919091013590565b600060208284031215610c7057600080fd5b8135610c7b81610bfb565b9392505050565b60008060408385031215610c9557600080fd5b8235610ca081610bfb565b946020939093013593505050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fd5b600060208284031215610cef57600080fd5b813567ffffffffffffffff80821115610d0757600080fd5b818401915084601f830112610d1b57600080fd5b813581811115610d2d57610d2d610cae565b604051601f82017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0908116603f01168101908382118183101715610d7357610d73610cae565b81604052828152876020848701011115610d8c57600080fd5b826020860160208301376000928101602001929092525095945050505050565b600060208284031215610dbe57600080fd5b81518015158114610c7b57600080fd5b600060208284031215610de057600080fd5b8151610c7b81610bfb565b600060208284031215610dfd57600080fd5b5051919050565b81810381811115610e3e577f4e487b7100000000000000000000000000000000000000000000000000000000600052601160045260246000fd5b92915050565b60006020808352835180602085015260005b81811015610e7257858101830151858201604001528201610e56565b5060006040828601015260407fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0601f830116850101925050509291505056fea26469706673582212202c48aee5de4959ef518786fa36afffd4b4a0c2f4af9e25741d18037fdf60170b64736f6c63430008180033000000000000000000000000a9ddd91249dfdd450e81e1c56ab60e1a6265170100000000000000000000000000000000000000000000000000000000000000600000000000000000000000003ef3d8ba38ebe18db133cec108f4d14ce00dd9ae0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ea05f9001fbdea6d4280879f283ff9d0b282060e0000000000000000000000000dd2ea40a3561c309c03b96108e78d06e8a1a99b000000000000000000000000f4c94b2fdc2efa4ad4b831f312e7ef74890705da";

        // Deploy using the specified CREATE2 deployer and a deterministic salt
        bytes memory callData = abi.encodeWithSignature("deployCreate2(bytes32,bytes)", salt, bytecode);
        (bool success, bytes memory returnData) = CREATEX.call(callData);

        require(success, "CREATE2 deployment failed");
        disputer = address(uint160(uint256(bytes32(returnData))));

        console.log("Disputer:", disputer);

        // // Transfer ownership to multisig
        // console.log("Transferred Disputer ownership to multisig:", multisig);
        // Disputer(disputer).transferOwnership(multisig);

        // // Send dispute tokens to disputer
        // uint256 amount = 100 * 10 ** MockToken(disputeToken).decimals();
        // if (MockToken(disputeToken).balanceOf(broadcaster) >= amount) {
        //     transferERC20Tokens(disputer, 100 * 10 ** MockToken(disputeToken).decimals(), disputeToken);
        //     console.log("Sent dispute tokens to disputer:", 100 * 10 ** MockToken(disputeToken).decimals());
        // }

        return address(disputer);
    }
}
