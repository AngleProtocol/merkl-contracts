// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { console } from "forge-std/console.sol";
import { Distributor } from "contracts/Distributor.sol";
import { MockToken, IERC20 } from "contracts/mock/MockToken.sol";
import { CommonUtils, ContractType } from "utils/src/CommonUtils.sol";
import { CHAIN_BASE } from "utils/src/Constants.sol";
import { StdAssertions } from "forge-std/Test.sol";

contract ClaimDistributor is CommonUtils, StdAssertions {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        /// TODO: COMPLETE
        uint256 chainId = CHAIN_BASE;
        IERC20 rewardToken = IERC20(0xC011882d0f7672D8942e7fE2248C174eeD640c8f);
        address claimer = 0x15775b23340C0f50E0428D674478B0e9D3D0a759;
        uint256 balanceToClaim = 1918683165360;
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = new bytes32[](17);
        proofs[0][0] = bytes32(0xb4273243bd0ec5add5e6d803f13bf6866ed1904d24626766ab2836454ba1ec0a);
        proofs[0][1] = bytes32(0x3ee0ead23e2fe3f664ccb5e13683f27e27a4d7fefa8405545fb6421244630375);
        proofs[0][2] = bytes32(0x69f54e33351af15236b33bb4695470f1af96cd1a9f154aa511ff16faa6886791);
        proofs[0][3] = bytes32(0xa9d77ad46850fbfb8c196c693acdbb0c6241a2e561a8b0073ec71297a565673d);
        proofs[0][4] = bytes32(0xe1b57f280e556c7f217e8d375f0cef7977a9467d5496d32bb8ec461f0d4c4f19);
        proofs[0][5] = bytes32(0x0fc7ddc7cc9ecc7f7b0be5692f671394f6245ffdabe5c0fd2062eb71b7c11826);
        proofs[0][6] = bytes32(0x94445a98fe6679760e5ac2edeacfe0bfa397f805c7adeaf3558a82accb78f201);
        proofs[0][7] = bytes32(0x14a6fec66cdfece5c73ec44196f1414326236131ff9a60350cca603e54985c4e);
        proofs[0][8] = bytes32(0x84679751230af3e3242ea1cecfc8daee3d2187ab647281cbf8c52e649a43e84c);
        proofs[0][9] = bytes32(0xc0fc15960178fe4d542c93e64ec58648e5ff17bd02b27f841bd6ab838fc5ee67);
        proofs[0][10] = bytes32(0x9b84efe5d11bc4de32ecd204c3962dd9270694d93a50e2840d763eaeac6c194b);
        proofs[0][11] = bytes32(0x5c8025dbe663cf4b4e19fbc7b1e54259af5822fd774fd60a98e7c7a60112efe0);
        proofs[0][12] = bytes32(0x301b573f9a6503ebe00ff7031a33cd41170d8b4c09a31fcafb9feb7529400a79);
        proofs[0][13] = bytes32(0xc89942ad2dcb0ac96d2620ef9475945bdbe6d40a9f6c4e9f6d9437a953bf881c);
        proofs[0][14] = bytes32(0xce6ca90077dc547f9a52a24d2636d659642fbae1d16c81c9e47c5747a472c63f);
        proofs[0][15] = bytes32(0xe34667d2e10b515dd1f7b29dcd7990d25ea9caa7a7de571c4fb221c0a8fc82a1);
        proofs[0][16] = bytes32(0x8316d6488fd22b823cc35ee673297ea2a753f0a89e5384ef20b38d053c881628);
        users[0] = claimer;
        tokens[0] = address(rewardToken);
        amounts[0] = balanceToClaim;
        /// END

        Distributor distributor = Distributor(_chainToContract(chainId, ContractType.Distributor));

        vm.startBroadcast(claimer);

        distributor.claim(users, tokens, amounts, proofs);

        assertEq(rewardToken.balanceOf(claimer), balanceToClaim);

        vm.stopBroadcast();
    }
}
