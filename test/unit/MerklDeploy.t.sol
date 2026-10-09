// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

import { MainDeployScript } from "../../scripts/merklDeploy.s.sol";
import { Distributor } from "../../contracts/Distributor.sol";
import { DistributionCreator } from "../../contracts/DistributionCreator.sol";
import { IAccessControlManager } from "../../contracts/interfaces/IAccessControlManager.sol";

contract MerklDeployHarness is MainDeployScript {
    function deployMerklContractsFromMerklDeployer(
        address accessControlManager
    ) external returns (DeploymentAddresses memory distributor, DeploymentAddresses memory creator) {
        MERKL_DEPLOYER_ADDRESS = EXPECTED_MERKL_DEPLOYER_ADDRESS;
        vm.startBroadcast(MERKL_DEPLOYER_ADDRESS);
        (distributor, creator) = deployMerklContracts(accessControlManager);
        vm.stopBroadcast();
    }
}

contract MerklDeployTest is Test {
    // Addresses of the contracts already deployed by the merkl deployer on every chain
    address constant DISTRIBUTOR_IMPLEMENTATION = 0x918261fa5Dd9C3b1358cA911792E9bDF3c5CCa35;
    address constant DISTRIBUTOR_PROXY = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address constant DISTRIBUTION_CREATOR_IMPLEMENTATION = 0x7Db28175B63f154587BbB1Cae62D39Ea80A23383;
    address constant DISTRIBUTION_CREATOR_PROXY = 0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;

    MerklDeployHarness harness;
    address merklDeployer;
    address accessControlManager;

    MainDeployScript.DeploymentAddresses distributor;
    MainDeployScript.DeploymentAddresses creator;

    function setUp() public {
        harness = new MerklDeployHarness();
        merklDeployer = harness.EXPECTED_MERKL_DEPLOYER_ADDRESS();
        accessControlManager = makeAddr("accessControlManager");
        vm.deal(merklDeployer, 1 ether);

        (distributor, creator) = harness.deployMerklContractsFromMerklDeployer(accessControlManager);
    }

    function test_deployMerklContracts_keepsCanonicalAddresses() public view {
        assertEq(distributor.implementation, DISTRIBUTOR_IMPLEMENTATION);
        assertEq(distributor.proxy, DISTRIBUTOR_PROXY);
        assertEq(creator.implementation, DISTRIBUTION_CREATOR_IMPLEMENTATION);
        assertEq(creator.proxy, DISTRIBUTION_CREATOR_PROXY);
        assertEq(vm.getNonce(merklDeployer), 5);
    }

    function test_deployMerklContracts_initializesProxiesAtDeployment() public {
        assertEq(address(Distributor(DISTRIBUTOR_PROXY).accessControlManager()), accessControlManager);
        assertEq(address(DistributionCreator(DISTRIBUTION_CREATOR_PROXY).accessControlManager()), accessControlManager);
        assertEq(DistributionCreator(DISTRIBUTION_CREATOR_PROXY).distributor(), DISTRIBUTOR_PROXY);
        assertEq(DistributionCreator(DISTRIBUTION_CREATOR_PROXY).defaultFees(), 0.03 gwei);

        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.expectRevert("Initializable: contract is already initialized");
        Distributor(DISTRIBUTOR_PROXY).initialize(IAccessControlManager(attacker));
        vm.expectRevert("Initializable: contract is already initialized");
        DistributionCreator(DISTRIBUTION_CREATOR_PROXY).initialize(IAccessControlManager(attacker), attacker, 0);
        vm.stopPrank();
    }
}
