// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import { Distributor, MerkleTree } from "../contracts/Distributor.sol";

interface IDistributorWithCore {
    function core() external view returns (address);
}

contract UpgradeDistributorTest is Test {
    Distributor public distributor;
    address public deployer;
    address public governor;
    address public updater;
    uint256 public chainId;

    // Storage snapshots before upgrade
    address public preUpgrade_accessControlManager;
    bytes32 public preUpgrade_merkleRoot;
    bytes32 public preUpgrade_treeRoot;
    bytes32 public preUpgrade_treeHash;
    bytes32 public preUpgrade_lastTreeRoot;
    bytes32 public preUpgrade_lastTreeHash;
    address public preUpgrade_disputeToken;
    address public preUpgrade_disputer;
    uint48 public preUpgrade_endOfDisputePeriod;
    uint48 public preUpgrade_disputePeriod;
    uint256 public preUpgrade_disputeAmount;
    uint256 public preUpgrade_updaterCanUpdate;
    uint128 public preUpgrade_upgradeabilityDeactivated;

    // Mapping of chainId to distributor address
    mapping(uint256 => address) public distributorAddresses;
    
    function setUp() public {
        // Setup environment variables
        deployer = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
        updater = 0x435046800Fb9149eE65159721A92cB7d50a7534b;
        
        // Fork BASE by default for CI/standard tests
        vm.createSelectFork(vm.envString("BASE_NODE_URI"));
        chainId = block.chainid;
        
        // Load distributor contract from mainnet
        distributor = Distributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);
        
        _setupUpgradeTest();
    }
    
    function _setupUpgradeTest() internal {
        // Try core() first, then fall back to accessControlManager()
        AccessControlEnumerableUpgradeable accessControlManager;
        try IDistributorWithCore(address(distributor)).core() returns (address coreAddress) {
            accessControlManager = AccessControlEnumerableUpgradeable(coreAddress);
        } catch {
            accessControlManager = AccessControlEnumerableUpgradeable(
                address(distributor.accessControlManager())
            );
        }
        
        // Get governor from access control manager
        bytes32 GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
        governor = accessControlManager.getRoleMember(GOVERNOR_ROLE, 0);
        
        // Store pre-upgrade state
        preUpgrade_accessControlManager = address(accessControlManager);
        preUpgrade_merkleRoot = distributor.getMerkleRoot();
        (preUpgrade_treeRoot, preUpgrade_treeHash) = distributor.tree();
        (preUpgrade_lastTreeRoot, preUpgrade_lastTreeHash) = distributor.lastTree();
        preUpgrade_disputeToken = address(distributor.disputeToken());
        preUpgrade_disputer = distributor.disputer();
        preUpgrade_endOfDisputePeriod = distributor.endOfDisputePeriod();
        preUpgrade_disputePeriod = distributor.disputePeriod();
        preUpgrade_disputeAmount = distributor.disputeAmount();
        preUpgrade_updaterCanUpdate = distributor.canUpdateMerkleRoot(updater);
        
        // Deploy new implementation
        vm.startPrank(deployer);
        address distributorImpl = address(new Distributor());
        vm.stopPrank();
        
        // Upgrade
        vm.startPrank(governor);
        distributor.upgradeTo(distributorImpl);
        vm.stopPrank();
    }

    function test_VerifyStorageSlots_Success() public {
        // Verify all storage slots remain unchanged after upgrade
        
        // Verify access control manager
        assertEq(
            address(distributor.accessControlManager()),
            preUpgrade_accessControlManager,
            "AccessControlManager should remain unchanged"
        );
        
        // Verify getMerkleRoot remains the same
        bytes32 merkleRoot = distributor.getMerkleRoot();
        assertEq(merkleRoot, preUpgrade_merkleRoot, "MerkleRoot should remain unchanged");
        assertTrue(merkleRoot != bytes32(0), "MerkleRoot should be non-zero");
        
        // Verify tree storage
        (bytes32 currentRoot, bytes32 currentHash) = distributor.tree();
        assertEq(currentRoot, preUpgrade_treeRoot, "Tree root should remain unchanged");
        assertEq(currentHash, preUpgrade_treeHash, "Tree hash should remain unchanged");
        
        // Verify lastTree storage
        (bytes32 lastRoot, bytes32 lastHash) = distributor.lastTree();
        assertEq(lastRoot, preUpgrade_lastTreeRoot, "LastTree root should remain unchanged");
        assertEq(lastHash, preUpgrade_lastTreeHash, "LastTree hash should remain unchanged");
        
        // Verify dispute token
        address disputeTokenAddr = address(distributor.disputeToken());
        assertEq(disputeTokenAddr, preUpgrade_disputeToken, "DisputeToken should remain unchanged");
        assertTrue(disputeTokenAddr != address(0), "DisputeToken should be non-zero");
        
        // Verify disputer
        address currentDisputer = distributor.disputer();
        assertEq(currentDisputer, preUpgrade_disputer, "Disputer should remain unchanged");
        
        // Verify dispute amount
        uint256 disputeAmount = distributor.disputeAmount();
        assertEq(disputeAmount, preUpgrade_disputeAmount, "DisputeAmount should remain unchanged");
        
        // Verify dispute period
        uint48 disputePeriod = distributor.disputePeriod();
        assertEq(disputePeriod, preUpgrade_disputePeriod, "DisputePeriod should remain unchanged");
        
        // Verify end of dispute period
        uint48 endOfDisputePeriod = distributor.endOfDisputePeriod();
        assertEq(endOfDisputePeriod, preUpgrade_endOfDisputePeriod, "EndOfDisputePeriod should remain unchanged");
        
        // Verify updater can update merkle root (0x435046800Fb9149eE65159721A92cB7d50a7534b)
        uint256 canUpdate = distributor.canUpdateMerkleRoot(updater);
        assertEq(canUpdate, preUpgrade_updaterCanUpdate, "Updater authorization should remain unchanged");
        assertEq(canUpdate, 1, "Updater should be authorized to update merkle root");
        
        // Verify upgradeability status
        uint128 upgradeabilityDeactivated = distributor.upgradeabilityDeactivated();
        assertEq(upgradeabilityDeactivated, 0, "Upgradeability status should remain unchanged");
    }

    function test_UpgradeTo_Revert_WhenNonGovernor() public {
        vm.startPrank(deployer);
        address distributorImpl = address(new Distributor());
        vm.stopPrank();
        
        // Should revert when non-governor tries to upgrade
        address nonGovernor = makeAddr("nonGovernor");
        vm.startPrank(nonGovernor);
        vm.expectRevert();
        distributor.upgradeTo(distributorImpl);
        vm.stopPrank();
    }

    function test_UpdateTree_Success_WhenAuthorizedUpdater() public {
        // Skip to after current dispute period
        vm.warp(distributor.endOfDisputePeriod() + 1);
        
        // Verify updater is authorized
        assertEq(distributor.canUpdateMerkleRoot(updater), 1, "Updater should be authorized");
        
        // Create new merkle tree
        MerkleTree memory newTree = MerkleTree({
            merkleRoot: keccak256(abi.encodePacked("new_test_root")),
            ipfsHash: bytes32(0)
        });
        
        // Record current values
        (bytes32 oldRoot, ) = distributor.tree();
        uint48 oldEndOfDisputePeriod = distributor.endOfDisputePeriod();
        
        // Update tree as authorized updater
        vm.prank(updater);
        distributor.updateTree(newTree);
        
        // Verify tree was updated
        (bytes32 currentRoot, bytes32 currentHash) = distributor.tree();
        assertEq(currentRoot, newTree.merkleRoot, "Tree root should be updated");
        assertEq(currentHash, newTree.ipfsHash, "Tree hash should be updated");
        
        // Verify lastTree was updated to old tree
        (bytes32 lastRoot, ) = distributor.lastTree();
        assertEq(lastRoot, oldRoot, "LastTree should store previous root");
        
        // Verify end of dispute period was updated
        uint48 newEndOfDisputePeriod = distributor.endOfDisputePeriod();
        assertTrue(newEndOfDisputePeriod > oldEndOfDisputePeriod, "EndOfDisputePeriod should be extended");
    }

    function test_UpdateTree_Revert_WhenUnauthorized() public {
        // Skip to after current dispute period
        vm.warp(distributor.endOfDisputePeriod() + 1);
        
        // Create new merkle tree
        MerkleTree memory newTree = MerkleTree({
            merkleRoot: keccak256(abi.encodePacked("unauthorized_root")),
            ipfsHash: bytes32(0)
        });
        
        // Try to update as unauthorized address
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        distributor.updateTree(newTree);
    }

    function test_UpdateTree_Revert_WhenDisputePeriodNotOver() public {
        // Warp to middle of dispute period
        vm.warp(distributor.endOfDisputePeriod() - 100);
        
        // Create new merkle tree
        MerkleTree memory newTree = MerkleTree({
            merkleRoot: keccak256(abi.encodePacked("early_root")),
            ipfsHash: bytes32(0)
        });
        
        // Try to update before dispute period ends
        vm.prank(updater);
        vm.expectRevert();
        distributor.updateTree(newTree);
    }


    function test_VerifyOperatorFunctionality_Success() public {
        // Verify operator mappings are preserved
        address testUser = makeAddr("testUser");
        address testOperator = makeAddr("testOperator");
        
        // Check that operator functionality is accessible
        vm.prank(testUser);
        distributor.toggleOperator(testUser, testOperator);
        
        // Verify operator was toggled
        uint256 operatorStatus = distributor.operators(testUser, testOperator);
        assertEq(operatorStatus, 1, "Operator should be toggled on");
        
        // Toggle off
        vm.prank(testUser);
        distributor.toggleOperator(testUser, testOperator);
        
        // Verify operator was toggled off
        operatorStatus = distributor.operators(testUser, testOperator);
        assertEq(operatorStatus, 0, "Operator should be toggled off");
    }

    function test_VerifyDisputeFunctionality_Success() public {
        // Verify dispute-related state is preserved and matches pre-upgrade values
        address currentDisputer = distributor.disputer();
        assertEq(currentDisputer, preUpgrade_disputer, "Disputer should remain unchanged");
        
        uint256 disputeAmt = distributor.disputeAmount();
        assertEq(disputeAmt, preUpgrade_disputeAmount, "Dispute amount should remain unchanged");
        
        uint48 disputePer = distributor.disputePeriod();
        assertEq(disputePer, preUpgrade_disputePeriod, "Dispute period should remain unchanged");
    }


    function test_VerifyGovernorCanToggleTrusted_Success() public {
        // Verify governor can still toggle trusted addresses
        address newTrusted = makeAddr("newTrusted");
        
        // Toggle on
        vm.prank(governor);
        distributor.toggleTrusted(newTrusted);
        
        // Verify trusted status
        uint256 trustedStatus = distributor.canUpdateMerkleRoot(newTrusted);
        assertEq(trustedStatus, 1, "Address should be trusted");
        
        // Toggle off
        vm.prank(governor);
        distributor.toggleTrusted(newTrusted);
        
        // Verify untrusted
        trustedStatus = distributor.canUpdateMerkleRoot(newTrusted);
        assertEq(trustedStatus, 0, "Address should be untrusted");
    }

    function test_VerifyGovernorCanUpdateDisputeSettings_Success() public {
        // Update dispute amount
        uint256 newDisputeAmount = preUpgrade_disputeAmount + 1e18;
        vm.prank(governor);
        distributor.setDisputeAmount(newDisputeAmount);
        
        // Verify update
        assertEq(distributor.disputeAmount(), newDisputeAmount, "Dispute amount should be updated");
        
        // Update dispute period
        uint48 newDisputePeriod = preUpgrade_disputePeriod + 1;
        vm.prank(governor);
        distributor.setDisputePeriod(newDisputePeriod);
        
        // Verify update
        assertEq(distributor.disputePeriod(), newDisputePeriod, "Dispute period should be updated");
    }
}
