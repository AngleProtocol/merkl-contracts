// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { NativeTokenUnwrapperImmutable } from "../contracts/partners/tokenWrappers/NativeTokenUnwrapperImmutable.sol";

contract DeployNativeTokenUnwrapper is BaseScript {
    // forge script scripts/deployNativeTokenUnwrapper.s.sol --rpc-url mainnet --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast --verify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address distributionCreator = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
        // ------------------------------------------------------------------------
        // TO EDIT
        address wrappedNative = _getWrappedNative();
        address holder = msg.sender;
        // ------------------------------------------------------------------------

        (string memory name, string memory symbol) = _getNativeTokenInfo();

        NativeTokenUnwrapperImmutable wrapper = new NativeTokenUnwrapperImmutable(
            wrappedNative,
            distributionCreator,
            holder,
            name,
            symbol
        );

        console.log("NativeTokenUnwrapperImmutable:", address(wrapper));
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Wrapped Native:", wrappedNative);

        vm.stopBroadcast();
    }

    function _getWrappedNative() internal view returns (address) {
        uint256 chainId = block.chainid;

        // Ethereum mainnet
        if (chainId == 1) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        // Optimism
        if (chainId == 10) return 0x4200000000000000000000000000000000000006;
        // BSC
        if (chainId == 56) return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        // Gnosis
        if (chainId == 100) return 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
        // Polygon
        if (chainId == 137) return 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        // Fantom
        if (chainId == 250) return 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
        // zkSync Era
        if (chainId == 324) return 0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;
        // Mantle
        if (chainId == 5000) return 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;
        // Base
        if (chainId == 8453) return 0x4200000000000000000000000000000000000006;
        // Mode
        if (chainId == 34443) return 0x4200000000000000000000000000000000000006;
        // Arbitrum
        if (chainId == 42161) return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        // Avalanche
        if (chainId == 43114) return 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        // Linea
        if (chainId == 59144) return 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;
        // Blast
        if (chainId == 81457) return 0x4300000000000000000000000000000000000004;
        // Scroll
        if (chainId == 534352) return 0x5300000000000000000000000000000000000004;
        // Berachain
        if (chainId == 80094) return 0x6969696969696969696969696969696969696969;

        revert("Unsupported chain: add wrapped native address");
    }

    function _getNativeTokenInfo() internal view returns (string memory name, string memory symbol) {
        uint256 chainId = block.chainid;

        // BNB Chain
        if (chainId == 56) return ("BNB", "BNB");
        // Gnosis (xDAI)
        if (chainId == 100) return ("xDAI", "xDAI");
        // Polygon (MATIC -> POL)
        if (chainId == 137) return ("POL", "POL");
        // Fantom
        if (chainId == 250) return ("Fantom", "FTM");
        // Mantle
        if (chainId == 5000) return ("Mantle", "MNT");
        // Avalanche
        if (chainId == 43114) return ("Avalanche", "AVAX");
        // Berachain
        if (chainId == 80094) return ("Bera", "BERA");

        // Default: ETH-based chains (Ethereum, Optimism, Base, Arbitrum, Linea, Blast, Scroll, Mode, zkSync, etc.)
        return ("Ether", "ETH");
    }
}
