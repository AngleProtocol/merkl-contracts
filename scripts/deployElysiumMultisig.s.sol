// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { BaseScript } from "./utils/Base.s.sol";
import { IGnosisSafe, IGnosisSafeProxyFactory } from "./utils/ISafe.sol";

/// @notice Angle Labs 4-of-6 multisig using Elysium's existing Safe v1.3.0 factory.
/// @dev Default forge script execution is a simulation. No Merkl deployer key is used.
/// Runtime hashes were checked against safe-global/safe-deployments commit
/// b45417dd009957effb3575928941e736f8fd37d1 (src/assets/v1.3.0).
contract DeployElysiumMultisig is BaseScript {
    address public constant DEPLOYER = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
    address public constant MERKL_DEPLOYER = 0x9f76a95AA7535bb0893cf88A146396e00ed21A12;
    address public constant FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    address public constant SINGLETON = 0x3E5c63644E683549055b9Be8653de26E0B4CD36E;
    address public constant FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    uint256 public constant THRESHOLD = 4;
    uint256 public constant SALT_NONCE = 0;

    function owners() public pure returns (address[] memory result) {
        result = new address[](6);
        result[0] = 0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002;
        result[1] = 0xf8b3b2aE2C97799249874A32f033b931e59fc349;
        result[2] = 0x34Eb88EAD486A09CAcD8DaBe013682Dc5F1DC41D;
        result[3] = 0x72b7BDdfd2AB1BAb6fce0aa8c3ba38953c3A4cef;
        result[4] = 0x6a75d4ddA3849F6755a0f83e5f9f29a4c9461EB3;
        result[5] = 0x957947b78857811a7C7bF62A0c6cd23c87adc7cC;
    }

    /// @dev Replays are rejected by the factory: the same initializer and salt map to the same CREATE2 address.
    /// The Merkl deployer nonce check only guarantees this deployment does not consume the nonce reserved
    /// for deterministic Merkl addresses.
    function run() external returns (address multisig) {
        require(block.chainid == 99901, "Wrong chain: expected Elysium 99901");
        require(broadcaster == DEPLOYER, "Expected regular deployer");
        require(vm.getNonce(MERKL_DEPLOYER) == 0, "Merkl deployer nonce must remain zero");
        require(FACTORY.codehash == 0x337d7f54be11b6ed55fef7b667ea5488db53db8320a05d1146aa4bd169a39a9b, "Unexpected factory bytecode");
        require(SINGLETON.codehash == 0x21842597390c4c6e3c1239e434a682b054bd9548eee5e9b1d6a4482731023c0f, "Unexpected singleton bytecode");
        require(
            FALLBACK_HANDLER.codehash == 0x03e69f7ce809e81687c69b19a7d7cca45b6d551ffdec73d9bb87178476de1abf,
            "Unexpected fallback handler bytecode"
        );

        console.log("Chain ID:", block.chainid);
        console.log("Sender:", broadcaster);
        console.log("Sender starting nonce:", uint256(vm.getNonce(broadcaster)));

        multisig = _deploy();

        verify(multisig);
        require(IGnosisSafe(multisig).nonce() == 0, "Unexpected multisig nonce");
        require(vm.getNonce(MERKL_DEPLOYER) == 0, "Merkl deployer nonce changed");
        console.log("Multisig:", multisig);
        console.log("Owners: 6; threshold: 4; version: 1.3.0");
        console.log("Merkl deployer nonce:", uint256(vm.getNonce(MERKL_DEPLOYER)));
    }

    /// @notice Read-only verification of the owners, threshold, modules, guard, singleton and fallback handler.
    /// @dev Does not check the Safe nonce, so it keeps working after the multisig executes transactions.
    function verify(address multisig) public view {
        require(multisig.code.length != 0, "No multisig code");
        IGnosisSafe account = IGnosisSafe(multisig);
        require(keccak256(bytes(account.VERSION())) == keccak256(bytes("1.3.0")), "Wrong multisig version");
        require(account.getThreshold() == THRESHOLD, "Wrong threshold");
        address[] memory actualOwners = account.getOwners();
        address[] memory expectedOwners = owners();
        require(actualOwners.length == expectedOwners.length, "Wrong owner count");
        for (uint256 i; i < expectedOwners.length; ++i) {
            require(actualOwners[i] == expectedOwners[i], "Wrong owner");
        }
        (address[] memory modules, address next) = account.getModulesPaginated(address(1), 1);
        require(modules.length == 0 && next == address(1), "Unexpected module");
        require(address(uint160(uint256(vm.load(multisig, bytes32(0))))) == SINGLETON, "Wrong singleton");
        require(vm.load(multisig, keccak256("guard_manager.guard.address")) == bytes32(0), "Unexpected guard");
        require(
            address(uint160(uint256(vm.load(multisig, keccak256("fallback_manager.handler.address"))))) == FALLBACK_HANDLER,
            "Wrong fallback handler"
        );
    }

    /// @dev Deploys and initializes atomically; no delegates, payments, guards or modules.
    function _deploy() internal broadcast returns (address) {
        bytes memory initializer = abi.encodeCall(
            IGnosisSafe.setup,
            (owners(), THRESHOLD, address(0), new bytes(0), FALLBACK_HANDLER, address(0), 0, payable(address(0)))
        );
        return IGnosisSafeProxyFactory(FACTORY).createProxyWithNonce(SINGLETON, initializer, SALT_NONCE);
    }
}
