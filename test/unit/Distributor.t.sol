// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Distributor, MerkleTree } from "../../contracts/Distributor.sol";
import { Fixture } from "../Fixture.t.sol";
import { IAccessControlManager } from "../../contracts/interfaces/IAccessControlManager.sol";
import { Errors } from "../../contracts/utils/Errors.sol";
import { MockClaimRecipient, MockClaimRecipientWrongReturn, MockNonClaimRecipient } from "../../contracts/mock/MockClaimRecipient.sol";

contract DistributorTest is Fixture {
    Distributor public distributor;
    Distributor public distributorImpl;

    function setUp() public virtual override {
        super.setUp();

        distributorImpl = new Distributor();
        distributor = Distributor(deployUUPS(address(distributorImpl), hex""));
        distributor.initialize(IAccessControlManager(address(accessControlManager)));

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
        d.initialize(IAccessControlManager(address(accessControlManager)));

        assertEq(address(accessControlManager), address(d.accessControlManager()));
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

    function test_Success_ShouldUpdateTree() public {
        vm.startPrank(governor);
        distributor.toggleTrusted(bob);
        assertEq(distributor.canUpdateMerkleRoot(bob), 1);
        vm.stopPrank();

        assertEq(distributor.getMerkleRoot(), bytes32(0));

        bytes32 root = getRoot();
        vm.startPrank(bob);
        distributor.updateTree(MerkleTree({ merkleRoot: root, ipfsHash: keccak256("IPFS_HASH") }));
        vm.stopPrank();

        vm.warp(distributor.endOfDisputePeriod() + 1);

        assertEq(distributor.getMerkleRoot(), root);
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

        vm.prank(governor);
        distributor.claim(users, tokens, amounts, proofs);

        assertEq(angle.balanceOf(address(alice)), aliceBalance + 1e18);
        assertEq(agEUR.balanceOf(address(bob)), bobBalance + 5e17);
    }

    function test_SuccessOperator() public {
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

contract Test_Distributor_claimWithRecipient is DistributorTest {
    function test_RevertWhen_NotWhitelisted() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        vm.warp(distributor.endOfDisputePeriod() + 1);

        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        users[0] = bob;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = alice;

        vm.expectRevert(Errors.NotWhitelisted.selector);
        vm.prank(alice);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);
    }

    function test_Success_WithCustomRecipient() public {
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);

        vm.warp(distributor.endOfDisputePeriod() + 1);

        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = bob;

        uint256 bobBalance = angle.balanceOf(address(bob));

        vm.prank(alice);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        assertEq(angle.balanceOf(address(bob)), bobBalance + 1e18);
    }

    function test_Success_UserCanOverrideDefaultRecipient() public {
        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Alice sets bob as default recipient
        vm.prank(alice);
        distributor.setClaimRecipient(bob, address(angle));
        assertEq(distributor.claimRecipient(alice, address(angle)), bob);

        // Setup claim data with charlie as recipient
        address charlie = address(0x999);
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = charlie;

        uint256 bobBalance = angle.balanceOf(bob);
        uint256 charlieBalance = angle.balanceOf(charlie);

        // Alice claims with charlie as recipient (should override default)
        vm.prank(alice);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        // Verify rewards went to charlie, not bob
        assertEq(angle.balanceOf(bob), bobBalance);
        assertEq(angle.balanceOf(charlie), charlieBalance + 1e18);
    }

    function test_Success_OperatorCannotOverrideRecipient() public {
        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Alice authorizes bob as operator
        vm.prank(alice);
        distributor.toggleOperator(alice, bob);

        // Setup claim data with charlie as recipient
        address charlie = address(0x999);
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = charlie; // Bob tries to set charlie as recipient

        uint256 aliceBalance = angle.balanceOf(alice);
        uint256 charlieBalance = angle.balanceOf(charlie);

        // Bob claims for alice but cannot override recipient (should go to alice)
        vm.prank(bob);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        // Verify rewards went to alice, not charlie
        assertEq(angle.balanceOf(alice), aliceBalance + 1e18);
        assertEq(angle.balanceOf(charlie), charlieBalance);
    }

    function test_Success_OperatorCannotOverrideDefaultRecipient() public {
        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Alice sets a default recipient (charlie)
        address charlie = address(0x999);
        vm.prank(alice);
        distributor.setClaimRecipient(charlie, address(angle));
        assertEq(distributor.claimRecipient(alice, address(angle)), charlie);

        // Alice authorizes bob as operator
        vm.prank(alice);
        distributor.toggleOperator(alice, bob);

        // Setup claim data with bob trying to set himself as recipient
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = bob; // Bob tries to set himself as recipient

        uint256 bobBalance = angle.balanceOf(bob);
        uint256 charlieBalance = angle.balanceOf(charlie);

        // Bob claims for alice but cannot override default recipient (should go to charlie)
        vm.prank(bob);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        // Verify rewards went to charlie (default recipient), not bob
        assertEq(angle.balanceOf(bob), bobBalance);
        assertEq(angle.balanceOf(charlie), charlieBalance + 1e18);
    }

    function test_Success_CallbackTriggeredWithData() public {
        // Deploy mock claim recipient
        MockClaimRecipient mockRecipient = new MockClaimRecipient();

        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Alice sets mock recipient as default
        vm.prank(alice);
        distributor.setClaimRecipient(address(mockRecipient), address(angle));

        // Setup claim data with custom data
        bytes memory customData = abi.encode("test", 12345);
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = address(0); // Zero address means use default
        datas[0] = customData;

        uint256 recipientBalance = angle.balanceOf(address(mockRecipient));
        assertEq(mockRecipient.callCount(), 0);

        // Alice claims with data
        vm.prank(alice);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        // Verify rewards went to mock recipient
        assertEq(angle.balanceOf(address(mockRecipient)), recipientBalance + 1e18);

        // Verify callback was triggered
        assertEq(mockRecipient.callCount(), 1);
        assertEq(mockRecipient.lastUser(), alice);
        assertEq(mockRecipient.lastToken(), address(angle));
        assertEq(mockRecipient.lastAmount(), 1e18);
        assertEq(mockRecipient.lastData(), customData);
    }

    function test_Success_CallbackWithWrongReturnReverts() public {
        // Deploy mock claim recipient with wrong return
        MockClaimRecipientWrongReturn mockRecipient = new MockClaimRecipientWrongReturn();

        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Alice sets mock recipient as default
        vm.prank(alice);
        distributor.setClaimRecipient(address(mockRecipient), address(angle));

        // Setup claim data with custom data
        bytes memory customData = abi.encode("test", 12345);
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = address(0);
        datas[0] = customData;

        uint256 recipientBalance = angle.balanceOf(address(mockRecipient));

        // Alice claims with data - should revert due to wrong return value
        vm.prank(alice);
        vm.expectRevert(Errors.InvalidReturnMessage.selector);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        // Verify no rewards were transferred due to revert
        assertEq(angle.balanceOf(address(mockRecipient)), recipientBalance);
    }

    function test_Success_CallbackWithNonImplementingContractDoesNotRevert() public {
        // Deploy mock non-recipient contract
        MockNonClaimRecipient mockRecipient = new MockNonClaimRecipient();

        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Alice sets mock recipient as default
        vm.prank(alice);
        distributor.setClaimRecipient(address(mockRecipient), address(angle));

        // Setup claim data with custom data
        bytes memory customData = abi.encode("test", 12345);
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = address(0);
        datas[0] = customData;

        uint256 recipientBalance = angle.balanceOf(address(mockRecipient));

        // Alice claims with data - should NOT revert (catch block handles it)
        vm.prank(alice);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        // Verify rewards were still transferred despite callback failure
        assertEq(angle.balanceOf(address(mockRecipient)), recipientBalance + 1e18);
    }

    function test_Success_NoCallbackWhenNoData() public {
        // Deploy mock claim recipient
        MockClaimRecipient mockRecipient = new MockClaimRecipient();

        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Alice sets mock recipient as default
        vm.prank(alice);
        distributor.setClaimRecipient(address(mockRecipient), address(angle));

        // Setup claim data without custom data
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        address[] memory recipients = new address[](1);
        bytes[] memory datas = new bytes[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        recipients[0] = address(0);
        datas[0] = ""; // Empty data

        uint256 recipientBalance = angle.balanceOf(address(mockRecipient));
        assertEq(mockRecipient.callCount(), 0);

        // Alice claims without data
        vm.prank(alice);
        distributor.claimWithRecipient(users, tokens, amounts, proofs, recipients, datas);

        // Verify rewards went to mock recipient
        assertEq(angle.balanceOf(address(mockRecipient)), recipientBalance + 1e18);

        // Verify callback was NOT triggered (no data)
        assertEq(mockRecipient.callCount(), 0);
    }
}

contract Test_Distributor_revokeUpgradeability is DistributorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.revokeUpgradeability();
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.revokeUpgradeability();
        assertEq(distributor.upgradeabilityDeactivated(), 1);

        // Verify that upgrades are no longer possible
        vm.startPrank(governor);
        Distributor impl = new Distributor();
        vm.expectRevert(Errors.NotUpgradeable.selector);
        distributor.upgradeTo(address(impl));
        vm.stopPrank();
    }
}

contract Test_Distributor_setEpochDuration is DistributorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.setEpochDuration(7200);
    }

    function test_Success() public {
        // Default epoch duration should be 3600
        assertEq(distributor.getEpochDuration(), 3600);

        vm.prank(governor);
        distributor.setEpochDuration(7200);

        assertEq(distributor.getEpochDuration(), 7200);

        // Verify that the new epoch duration affects dispute period calculations
        vm.prank(governor);
        distributor.updateTree(MerkleTree({ merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH") }));

        // End of dispute period should be rounded up to next 2-hour mark (7200 seconds) plus dispute period
        uint256 expectedEnd = ((block.timestamp - 1) / 7200 + 1 + distributor.disputePeriod()) * 7200;
        assertEq(distributor.endOfDisputePeriod(), expectedEnd);
    }
}

contract Test_Distributor_toggleMainOperatorStatus is DistributorTest {
    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.prank(alice);
        vm.expectRevert(Errors.NotGovernorOrGuardian.selector);
        distributor.toggleMainOperatorStatus(bob, address(angle));

        vm.prank(guardian);
        vm.expectRevert(Errors.NotGovernor.selector);
        distributor.toggleMainOperatorStatus(bob, address(0));
    }

    function test_Success_Governor() public {
        // Initial state - operator should not be whitelisted
        assertEq(distributor.mainOperators(bob, address(angle)), 0);

        // Governor toggles operator on
        vm.prank(governor);
        distributor.toggleMainOperatorStatus(bob, address(angle));
        assertEq(distributor.mainOperators(bob, address(angle)), 1);

        // Governor toggles operator off
        vm.prank(governor);
        distributor.toggleMainOperatorStatus(bob, address(angle));
        assertEq(distributor.mainOperators(bob, address(angle)), 0);
    }

    function test_Success_Guardian() public {
        // Initial state - operator should not be whitelisted
        assertEq(distributor.mainOperators(bob, address(angle)), 0);

        // Guardian toggles operator on
        vm.prank(guardian);
        distributor.toggleMainOperatorStatus(bob, address(angle));
        assertEq(distributor.mainOperators(bob, address(angle)), 1);

        // Guardian toggles operator off
        vm.prank(guardian);
        distributor.toggleMainOperatorStatus(bob, address(angle));
        assertEq(distributor.mainOperators(bob, address(angle)), 0);
    }

    function test_Success_WithZeroAddress() public {
        // Test with zero address for token (applies to all tokens)
        assertEq(distributor.mainOperators(bob, address(0)), 0);

        vm.prank(governor);
        distributor.toggleMainOperatorStatus(bob, address(0));
        assertEq(distributor.mainOperators(bob, address(0)), 1);

        vm.prank(governor);
        distributor.toggleMainOperatorStatus(bob, address(0));
        assertEq(distributor.mainOperators(bob, address(0)), 0);
    }

    function test_Success_AllowsClaimingWhenEnabled() public {
        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Setup claim data
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        // Bob cannot claim for alice initially
        vm.prank(bob);
        vm.expectRevert(Errors.NotWhitelisted.selector);
        distributor.claim(users, tokens, amounts, proofs);

        // Enable bob as main operator for angle token
        vm.prank(governor);
        distributor.toggleMainOperatorStatus(bob, address(angle));

        uint256 aliceBalance = angle.balanceOf(address(alice));

        // Now bob can claim for alice
        vm.prank(bob);
        distributor.claim(users, tokens, amounts, proofs);

        assertEq(angle.balanceOf(address(alice)), aliceBalance + 1e18);
    }
    function test_Success_AllowsClaimingWhenEnabledForAll() public {
        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Setup claim data
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        // Bob cannot claim for alice initially
        vm.prank(bob);
        vm.expectRevert(Errors.NotWhitelisted.selector);
        distributor.claim(users, tokens, amounts, proofs);

        // Enable bob as main operator for angle token
        vm.prank(governor);
        distributor.toggleMainOperatorStatus(bob, address(0));

        uint256 aliceBalance = angle.balanceOf(address(alice));

        // Now bob can claim for alice
        vm.prank(bob);
        distributor.claim(users, tokens, amounts, proofs);

        assertEq(angle.balanceOf(address(alice)), aliceBalance + 1e18);
    }
    function test_Success_AllowsClaimingWhenEnabledForOne() public {
        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Setup claim data
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        // Bob cannot claim for alice initially
        vm.prank(bob);
        vm.expectRevert(Errors.NotWhitelisted.selector);
        distributor.claim(users, tokens, amounts, proofs);

        // Enable bob as main operator for angle token
        vm.prank(alice);
        distributor.toggleOperator(alice, address(bob));

        uint256 aliceBalance = angle.balanceOf(address(alice));

        // Now bob can claim for alice
        vm.prank(bob);
        distributor.claim(users, tokens, amounts, proofs);

        assertEq(angle.balanceOf(address(alice)), aliceBalance + 1e18);
    }
    function test_Success_AllowsClaimingWhenEnabledForAllByUser() public {
        // Setup merkle tree
        vm.prank(governor);
        distributor.updateTree(
            MerkleTree({
                merkleRoot: bytes32(0x0b70a97c062cb747158b89e27df5bbda859ba072232efcbe92e383e9d74b8555),
                ipfsHash: keccak256("IPFS_HASH")
            })
        );

        angle.mint(address(distributor), 1e18);
        vm.warp(distributor.endOfDisputePeriod() + 1);

        // Setup claim data
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0x6f46ee2909b99367a0d9932a11f1bdb85c9354480c9de277d21086f9a8925c0a);
        users[0] = alice;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        // Bob cannot claim for alice initially
        vm.prank(bob);
        vm.expectRevert(Errors.NotWhitelisted.selector);
        distributor.claim(users, tokens, amounts, proofs);

        // Enable bob as main operator for angle token
        vm.prank(alice);
        distributor.toggleOperator(alice, address(0));

        uint256 aliceBalance = angle.balanceOf(address(alice));

        // Now bob can claim for alice
        vm.prank(bob);
        distributor.claim(users, tokens, amounts, proofs);

        assertEq(angle.balanceOf(address(alice)), aliceBalance + 1e18);
    }
}
