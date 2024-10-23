// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Distributor, MerkleTree } from "../../contracts/Distributor.sol";
import { Fixture } from "../Fixture.t.sol";
import { IAccessControlManager } from "../../contracts/interfaces/IAccessControlManager.sol";
import { Errors } from "../../contracts/utils/Errors.sol";

contract DistributorTest is Fixture {
    Distributor public distributor;
    Distributor public distributorImpl;

    function setUp() public virtual override {
        super.setUp();

        distributorImpl = new Distributor();
        distributor = Distributor(deployUUPS(address(distributorImpl), hex""));
        distributor.initialize(IAccessControlManager(address(AccessControlManager)));

        vm.startPrank(governor);
        distributor.setDisputeAmount(1e18);
        distributor.setDisputePeriod(1 days);
        distributor.setDisputeToken(angle);
        vm.stopPrank();

        angle.mint(address(alice), 100e18);
    }

    function getRoot() public pure returns (bytes32) {
        return keccak256(abi.encodePacked("MERKLE_ROOT"));
    }
}

contract Test_Distributor_Initialize is DistributorTest {
    Distributor d;

    function setUp() public override {
        super.setUp();
        d = Distributor(deployUUPS(address(new Distributor()), hex""));
    }

    function test_RevertWhen_CalledOnImplem() public {
        vm.expectRevert("Initializable: contract is already initialized");
        distributorImpl.initialize(IAccessControlManager(address(0)));
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        d.initialize(IAccessControlManager(address(0)));
    }

    function test_Success() public {
        d.initialize(IAccessControlManager(address(AccessControlManager)));

        assertEq(address(AccessControlManager), address(d.accessControlManager()));
    }
}

contract Test_Distributor_toggleTrusted is DistributorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.toggleTrusted(address(bob));
    }

    function test_Success() public {
        vm.startPrank(governor);
        distributor.toggleTrusted(bob);
        assertEq(distributor.canUpdateMerkleRoot(bob), 1);
        distributor.toggleTrusted(bob);
        assertEq(distributor.canUpdateMerkleRoot(bob), 0);
        vm.stopPrank();
    }
}

contract Test_Distributor_toggleOperator is DistributorTest {
    function test_RevertWhen_NotTrusted() public {
        vm.expectRevert(Errors.NotTrusted.selector);
        distributor.toggleOperator(bob, alice);
    }

    function test_Success() public {
        vm.prank(bob);
        distributor.toggleOperator(bob, alice);
        assertEq(distributor.operators(bob, alice), 1);

        vm.prank(governor);
        distributor.toggleOperator(bob, alice);
        assertEq(distributor.operators(bob, alice), 0);
        vm.stopPrank();
    }
}

contract Test_Distributor_recoverERC20 is DistributorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.recoverERC20(address(0), address(0), 0);
    }

    function test_Success() public {
        uint256 amount = 1e18;
        angle.mint(address(distributor), amount);

        vm.prank(governor);
        distributor.recoverERC20(address(angle), address(governor), amount);
        assertEq(angle.balanceOf(address(distributor)), 0);
        assertEq(angle.balanceOf(address(governor)), amount);
    }
}

contract Test_Distributor_setDisputePeriod is DistributorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.setDisputePeriod(0);
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.setDisputePeriod(1);
        assertEq(distributor.disputePeriod(), 1);
    }
}

contract Test_Distributor_setDisputeToken is DistributorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.setDisputeToken(angle);
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.setDisputeToken(angle);
        assertEq(address(distributor.disputeToken()), address(angle));
    }
}

contract Test_Distributor_setDisputeAmount is DistributorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.setDisputeAmount(0);
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.setDisputeAmount(1);
        assertEq(distributor.disputeAmount(), 1);
    }
}

contract Test_Distributor_updateTree is DistributorTest {
    function test_RevertWhen_NotTrusted() public {
        vm.expectRevert(Errors.NotTrusted.selector);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));
    }

    function test_RevertWhen_DisputeOngoing() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.expectRevert(Errors.NotTrusted.selector);
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));
    }

    function test_RevertWhen_DisputeNotFinished() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.warp(distributor.endOfDisputePeriod() + 1);

        vm.expectRevert(Errors.NotTrusted.selector);
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        (bytes32 merkleRoot, bytes32 ipfsHash) = distributor.tree();
        assertEq(merkleRoot, getRoot());
        assertEq(ipfsHash, keccak256("IPFS_HASH"));

        (merkleRoot, ipfsHash) = distributor.lastTree();
        assertEq(merkleRoot, bytes32(0));
        assertEq(ipfsHash, bytes32(0));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        merkleRoot = distributor.getMerkleRoot();
        assertEq(merkleRoot, bytes32(0));

        vm.warp(distributor.endOfDisputePeriod() + 1);
        merkleRoot = distributor.getMerkleRoot();
        assertEq(merkleRoot, getRoot());

        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HAS") }));

        (merkleRoot, ipfsHash) = distributor.lastTree();
        assertEq(merkleRoot, getRoot());
        assertEq(ipfsHash, keccak256("IPFS_HASH"));
    }
}

contract Test_Distributor_revokeTree is DistributorTest {
    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.revokeTree();
    }

    function test_RevertWhen_UnresolvedDispute() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.expectRevert(Errors.UnresolvedDispute.selector);
        vm.prank(governor);
        distributor.revokeTree();
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.prank(governor);
        distributor.revokeTree();

        (bytes32 merkleRoot, bytes32 ipfsHash) = distributor.tree();
        (bytes32 lastMerkleRoot, bytes32 lastIpfsHash) = distributor.lastTree();

        assertEq(merkleRoot, lastMerkleRoot);
        assertEq(ipfsHash, lastIpfsHash);
        assertEq(distributor.endOfDisputePeriod(), 0);
    }
}

contract Test_Distributor_disputeTree is DistributorTest {
    function test_RevertWhen_UnresolvedDispute() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.expectRevert(Errors.UnresolvedDispute.selector);
        vm.prank(governor);
        distributor.disputeTree("wrong");
    }

    function test_RevertWhen_InvalidDispute() public {
        vm.expectRevert(Errors.InvalidDispute.selector);
        vm.prank(governor);
        distributor.disputeTree("wrong");
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        assertEq(distributor.disputer(), address(alice));
    }
}

contract Test_Distributor_resolveDispute is DistributorTest {
    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.resolveDispute(true);
    }

    function test_RevertWhen_NoDispute() public {
        vm.expectRevert(Errors.NoDispute.selector);
        vm.prank(governor);
        distributor.resolveDispute(true);
    }

    function test_SuccessValid() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        uint256 balance = angle.balanceOf(address(alice));

        vm.warp(distributor.endOfDisputePeriod() + 1);
        vm.prank(governor);
        distributor.resolveDispute(true);

        assertEq(distributor.disputer(), address(0));
        assertEq(distributor.endOfDisputePeriod(), 0);
        (bytes32 merkleRoot, bytes32 ipfsHash) = distributor.tree();
        (bytes32 lastMerkleRoot, bytes32 lastIpfsHash) = distributor.lastTree();
        assertEq(merkleRoot, lastMerkleRoot);
        assertEq(ipfsHash, lastIpfsHash);
        assertEq(angle.balanceOf(address(alice)), balance + distributor.disputeAmount());
    }

    function test_SuccessInvalid() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        uint256 balance = angle.balanceOf(address(alice));
        uint256 governorBalance = angle.balanceOf(address(governor));

        vm.warp(distributor.endOfDisputePeriod() + 1);
        vm.prank(governor);
        distributor.resolveDispute(false);

        assertEq(distributor.disputer(), address(0));
        (bytes32 merkleRoot, bytes32 ipfsHash) = distributor.tree();
        assertEq(merkleRoot, getRoot());
        assertEq(ipfsHash, keccak256("IPFS_HASH"));
        assertEq(angle.balanceOf(address(alice)), balance);
        assertEq(angle.balanceOf(address(governor)), governorBalance + distributor.disputeAmount());
    }
}

contract Test_Distributor_claim is DistributorTest {
    function test_RevertWhen_NotWhitelisted() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() + 1);

        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = new bytes32[](1);
        users[0] = bob;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        vm.expectRevert(Errors.NotWhitelisted.selector);
        vm.prank(alice);
        distributor.claim(users, tokens, amounts, proofs);
    }

    function test_RevertWhen_InvalidLengths() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() + 1);

        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](0);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.expectRevert(Errors.InvalidLengths.selector);
        distributor.claim(users, tokens, amounts, proofs);

        users = new address[](2);
        vm.expectRevert(Errors.InvalidLengths.selector);
        distributor.claim(users, tokens, amounts, proofs);

        users = new address[](1);
        proofs = new bytes32[][](0);
        vm.expectRevert(Errors.InvalidLengths.selector);
        distributor.claim(users, tokens, amounts, proofs);

        proofs = new bytes32[][](1);
        tokens = new address[](0);
        vm.expectRevert(Errors.InvalidLengths.selector);
        distributor.claim(users, tokens, amounts, proofs);

        tokens = new address[](1);
        amounts = new uint256[](0);
        vm.expectRevert(Errors.InvalidLengths.selector);
        distributor.claim(users, tokens, amounts, proofs);
    }

    function test_RevertWhen_InvalidProof() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() + 1);

        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = new bytes32[](1);
        users[0] = bob;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(bob);
        distributor.claim(users, tokens, amounts, proofs);
    }

    function test_SuccessGovernor() public {
        console.log(alice, bob, address(angle), address(agEUR));
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        agEUR.mint(address(distributor), 5e17);

        vm.warp(distributor.endOfDisputePeriod() + 1);

        bytes32[][] memory proofs = new bytes32[][](2);
        address[] memory users = new address[](2);
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        proofs[1] = new bytes32[](1);
        proofs[1][0] = bytes32(0x3a64e591d79db8530701e6f3dbdd95dc74681291b327d0ce4acc97024a61430c);
        users[1] = bob;
        tokens[1] = address(agEUR);
        amounts[1] = 5e17;

        // uint256 aliceBalance = angle.balanceOf(address(alice));
        // uint256 bobBalance = agEUR.balanceOf(address(bob));

        vm.prank(governor);
        vm.expectRevert(Errors.NotWhitelisted.selector); // governor not able to claim anymore
        distributor.claim(users, tokens, amounts, proofs);

        // assertEq(angle.balanceOf(address(alice)), aliceBalance + 1e18);
        // assertEq(agEUR.balanceOf(address(bob)), bobBalance + 5e17);
    }

    function test_SuccessOperator() public {
        console.log(alice, bob, address(angle), address(agEUR));
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        agEUR.mint(address(distributor), 5e17);

        vm.warp(distributor.endOfDisputePeriod() + 1);

        bytes32[][] memory proofs = new bytes32[][](2);
        address[] memory users = new address[](2);
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        proofs[1] = new bytes32[](1);
        proofs[1][0] = bytes32(0x3a64e591d79db8530701e6f3dbdd95dc74681291b327d0ce4acc97024a61430c);
        users[1] = bob;
        tokens[1] = address(agEUR);
        amounts[1] = 5e17;

        uint256 aliceBalance = angle.balanceOf(address(alice));
        uint256 bobBalance = agEUR.balanceOf(address(bob));

        vm.prank(alice);
        distributor.toggleOperator(alice, bob);

        vm.prank(bob);
        distributor.claim(users, tokens, amounts, proofs);

        assertEq(angle.balanceOf(address(alice)), aliceBalance + 1e18);
        assertEq(agEUR.balanceOf(address(bob)), bobBalance + 5e17);
    }
}
