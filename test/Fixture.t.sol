// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import { Test, stdError } from "forge-std/Test.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { console } from "forge-std/console.sol";

import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { DistributionCreatorWithDistributions } from "../contracts/DistributionCreatorWithDistributions.sol";
import { MockTokenPermit } from "../contracts/mock/MockTokenPermit.sol";
import { MockUniswapV3Pool } from "../contracts/mock/MockUniswapV3Pool.sol";
import { MockAccessControl } from "../contracts/mock/MockAccessControl.sol";
import { IAccessControlManager } from "../contracts/interfaces/IAccessControlManager.sol";
import { UUPSHelper } from "../contracts/utils/UUPSHelper.sol";
import { MockTokenPermit } from "../contracts/mock/MockTokenPermit.sol";
import { MockUniswapV3Pool } from "../contracts/mock/MockUniswapV3Pool.sol";
import { MockAccessControl } from "../contracts/mock/MockAccessControl.sol";

contract Fixture is Test {
    uint32 public constant EPOCH_DURATION = 3600;

    MockTokenPermit public angle;
    MockTokenPermit public agEUR;
    MockTokenPermit public token0;
    MockTokenPermit public token1;

    MockAccessControl public accessControlManager;
    MockUniswapV3Pool public pool;
    DistributionCreatorWithDistributions public creatorImpl;
    DistributionCreatorWithDistributions public creator;

    address public alice;
    address public bob;
    address public charlie;
    address public dylan;
    address public guardian;
    address public governor;

    function setUp() public virtual {
        alice = vm.addr(1);
        bob = vm.addr(2);
        charlie = vm.addr(3);
        dylan = vm.addr(4);
        guardian = address(uint160(uint256(keccak256(abi.encodePacked("guardian")))));
        governor = address(uint160(uint256(keccak256(abi.encodePacked("governor")))));

        vm.label(address(angle), "ANGLE");
        vm.label(address(agEUR), "agEUR");
        vm.label(address(token0), "TOKEN0");
        vm.label(address(token1), "TOKEN1");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(dylan, "Dylan");
        vm.label(guardian, "Guardian");
        vm.label(governor, "Governor");

        // tokens
        angle = MockTokenPermit(address(new MockTokenPermit("ANGLE", "ANGLE", 18)));
        agEUR = MockTokenPermit(address(new MockTokenPermit("agEUR", "agEUR", 18)));
        token0 = MockTokenPermit(address(new MockTokenPermit("token0", "TOKEN0", 18)));
        token1 = MockTokenPermit(address(new MockTokenPermit("token1", "TOKEN1", 18)));

        // side
        accessControlManager = new MockAccessControl();
        pool = new MockUniswapV3Pool();

        // DistributionCreator
        creatorImpl = new DistributionCreatorWithDistributions();
        creator = DistributionCreatorWithDistributions(deployUUPS(address(creatorImpl), hex""));

        // Set
        pool.setToken(address(token0), 0);
        pool.setToken(address(token1), 1);
        accessControlManager.toggleGuardian(address(guardian));
        accessControlManager.toggleGovernor(address(governor));
        creator.initialize(IAccessControlManager(address(accessControlManager)), address(bob), 1e8);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function deployUUPS(address implementation, bytes memory data) public returns (address) {
        return address(new ERC1967Proxy(implementation, data));
    }
}
