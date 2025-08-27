// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";

import { BaseScript } from "./utils/Base.s.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JsonReader } from "@utils/JsonReader.sol";
import { ContractType } from "@utils/Constants.sol";

import { PullTokenWrapperWithAllow } from "../contracts/partners/tokenWrappers/PullTokenWrapperWithAllow.sol";
import { Distributor } from "../contracts/Distributor.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

contract toggleOperatorBatch is BaseScript {
    // forge script scripts/toggleOperatorBatch.s.sol --rpc-url mainnet --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address distributor = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

        address operator = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

        // Ethereum
        
        Distributor(distributor).toggleOperator(0x529619a10129396a2F642cae32099C1eA7FA2834, 0xb08AB4332AD871F89da24df4751968A61e58013c);
        Distributor(distributor).toggleOperator(0x4402fe14C4C3ad83e468B426966B49195257E470, 0x82b7ab2Ef4e553A443c6cC05b1577f0B5267BF86);
        Distributor(distributor).toggleOperator(0xEA8c9Dacf681FbB0760bc2FC5e21475f3A234F75, 0x40326059F14c9c23e3B9E76c37282B8798138E0F);
        Distributor(distributor).toggleOperator(0xE928099Fc939aF47F8658B4bC50d961364d29C1d, 0xa7218a037F3713C0Ce03a1CAa3C471A95880E608);

        // Katana
        /*
        Distributor(distributor).toggleOperator(0xEA79C91540C7E884e6E0069Ce036E52f7BbB1194, operator);
        Distributor(distributor).toggleOperator(0x37a79Bfb9F645F8Ed0a9ead9c722710D8f47C431, operator);
        Distributor(distributor).toggleOperator(0x543CC24962b540430DD1121E83E8564770Da6810, operator);
        Distributor(distributor).toggleOperator(0x156C729C78076b7cd815D01Ca6967c00c5ac8D9C, operator);
        Distributor(distributor).toggleOperator(0xF7EDe5332c6b4A235be4aA3c019222CFe72e984F, operator);
        Distributor(distributor).toggleOperator(0xC1Ec6d26902949Bf6cbb0c9859dbEAD1E87FB243, operator);
        Distributor(distributor).toggleOperator(0x78EC25FBa1bAf6b7dc097Ebb8115A390A2a4Ee12, operator);
        Distributor(distributor).toggleOperator(0xD46dFDAA7cAA8739B0e3274e2C085dFFc8d4776A, operator);
        Distributor(distributor).toggleOperator(0x58B369aEC52DD904f70122cF72ed311f7AAe3bAc, operator);
        Distributor(distributor).toggleOperator(0x0a1937F0D7f15B9ADee5d96616f269a0C6749C6d, operator);
        */
        

        // Base
        /*
        Distributor(distributor).toggleOperator(0xEF34B4Dcb851385b8F3a8ff460C34aDAFD160802, operator);
        Distributor(distributor).toggleOperator(0xd5428B889621Eee8060fc105AA0AB0Fa2e344468, operator);
        Distributor(distributor).toggleOperator(0x985CC9c306Bfe075F7c67EC275fb0b80F0b21976, operator);
        Distributor(distributor).toggleOperator(0xB9acb02818BDDD3aC178fa51a0587101E54748B0, operator);
        Distributor(distributor).toggleOperator(0x7bc9E2D216B22611D9805C12E0C682391720752F, operator);
        Distributor(distributor).toggleOperator(0x953370e91B70897A0cECc97B58E99D7946C841dE, operator);
        Distributor(distributor).toggleOperator(0xF115C134c23C7A05FBD489A8bE3116EbF54B0D9f, operator);
        Distributor(distributor).toggleOperator(0xBDD79a7DF622E9d9e19a7d92Bc7ea212FA0D2F3E, operator);
        Distributor(distributor).toggleOperator(0xa72a60e6167E8fC5e523184911475c4B37B835E2, operator);
        */
        

        vm.stopBroadcast();
    }
}
