// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "../utils/Base.s.sol";
import { Disputer } from "../../contracts/Disputer.sol";
import { Distributor } from "../../contracts/Distributor.sol";
import { JsonReader } from "../utils/JsonReader.sol";

// Base contract with shared constants and utilities
contract DisputerScript is BaseScript, JsonReader {
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
        address angleLabs = readAddress(chainId, "AngleLabs");
        address distributor = readAddress(chainId, "Merkl.Distributor");

        address disputer = address(
            new Disputer{ salt: vm.envBytes32("DEPLOY_SALT") }(
                broadcaster,
                DISPUTER_WHITELIST,
                Distributor(distributor)
            )
        );
        Disputer(disputer).transferOwnership(angleLabs);

        console.log("Disputer deployed at:", disputer);
    }
}

// SetDistributor scrip
contract SetDistributor is DisputerScript {
    function run(Distributor newDistributor) external broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");

        Disputer(disputerAddress).setDistributor(newDistributor);

        console.log("Distributor updated to:", address(newDistributor));
    }
}

// AddToWhitelist scrip
contract AddToWhitelist is DisputerScript {
    function run(address account) external broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");

        Disputer(disputerAddress).addToWhitelist(account);

        console.log("Address added to whitelist:", account);
    }
}

// RemoveFromWhitelist scrip
contract RemoveFromWhitelist is DisputerScript {
    function run(address account) external broadcast {
        uint256 chainId = block.chainid;
        address disputerAddress = readAddress(chainId, "Merkl.Disputer");

        Disputer(disputerAddress).removeFromWhitelist(account);

        console.log("Address removed from whitelist:", account);
    }
}
