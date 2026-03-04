// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { BaseScript } from "./utils/Base.s.sol";

interface IGnosisSafeProxyFactory {
    function createProxyWithNonce(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address proxy);
}

interface IGnosisSafe {
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function VERSION() external view returns (string memory);
}

// forge script scripts/deploySafe.s.sol --rpc-url $RPC_URL --broadcast -vvvv
contract DeploySafeScript is BaseScript {
    // Gensyn Safe contracts (v1.3.0)
    address constant SAFE_SINGLETON   = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;
    address constant SAFE_FACTORY     = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    address constant FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;

    // TODO: set your 3 owners before running
    address constant OWNER_1 = address(0x8f02b4a44Eacd9b8eE7739aa0BA58833DD45d002);
    address constant OWNER_2 = address(0xf8b3b2aE2C97799249874A32f033b931e59fc349);
    address constant OWNER_3 = address(0x34Eb88EAD486A09CAcD8DaBe013682Dc5F1DC41D);

    uint256 constant THRESHOLD  = 2;
    uint256 constant SALT_NONCE = 0;

    uint256 private DEPLOYER_PRIVATE_KEY;

    function run() external {
        DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

        require(OWNER_1 != address(0) && OWNER_2 != address(0) && OWNER_3 != address(0), "Set owners");

        address[] memory owners = new address[](3);
        owners[0] = OWNER_1;
        owners[1] = OWNER_2;
        owners[2] = OWNER_3;

        bytes memory initializer = abi.encodeCall(
            IGnosisSafe.setup,
            (
                owners,
                THRESHOLD,
                address(0),         // no delegate call
                new bytes(0),       // no delegate call data
                FALLBACK_HANDLER,
                address(0),         // no payment token
                0,                  // no payment
                payable(address(0)) // no payment receiver
            )
        );

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        address safe = IGnosisSafeProxyFactory(SAFE_FACTORY).createProxyWithNonce(
            SAFE_SINGLETON,
            initializer,
            SALT_NONCE
        );

        vm.stopBroadcast();

        console.log("\n=== Safe Deployed ===");
        console.log("Address:", safe);

        // Verify (no broadcast needed — read-only calls)
        address[] memory deployedOwners = IGnosisSafe(safe).getOwners();
        uint256 threshold = IGnosisSafe(safe).getThreshold();
        string memory version = IGnosisSafe(safe).VERSION();

        console.log("\n=== Verification ===");
        console.log("Version  :", version);
        console.log("Threshold:", threshold);
        console.log("Owners:");
        for (uint256 i = 0; i < deployedOwners.length; i++) {
            console.log(" -", deployedOwners[i]);
        }

        require(keccak256(bytes(version)) == keccak256(bytes("1.3.0")), "Version mismatch");
        require(threshold == THRESHOLD, "Threshold mismatch");
        require(deployedOwners.length == owners.length, "Owners count mismatch");
        console.log("\nAll checks passed!");
    }
}
