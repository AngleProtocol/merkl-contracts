// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { MezoWrapper } from "../contracts/partners/tokenWrappers/MezoWrapper.sol";

contract DeployMezoWrapper is BaseScript {
    // forge script scripts/deployMezoWrapper.s.sol --rpc-url mezo --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;

        // ------------------------------------------------------------------------
        // TO EDIT
        address underlying = 0x7B7c000000000000000000000000000000000001;
        address holder = 0x6b57b0Ef5594a5820fD473353180442764d8601D;
        address mezoStaking = 0xb90fdAd3DFD180458D62Cc6acedc983D78E20122;
        uint256 lockDuration = 0;
        string memory name = "veMEZO (wrapped)";
        string memory symbol = "veMEZO";
        // ------------------------------------------------------------------------

        MezoWrapper wrapper = new MezoWrapper(
            underlying,
            distributionCreator,
            holder,
            mezoStaking,
            lockDuration,
            name,
            symbol
        );

        console.log("MezoWrapper:", address(wrapper));

        vm.stopBroadcast();
    }
}
