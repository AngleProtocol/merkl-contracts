// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Distributor, MerkleTree } from "../../../contracts/Distributor.sol";
import "../Fixture.t.sol";

contract DistributorCreatorTest is Fixture {
    Distributor public distributor;
    Distributor public distributorImpl;
    bytes32[] public hashes;

    struct Claim {
        address user;
        address token;
        uint256 amount;
    }

    function setUp() public virtual override {
        super.setUp();

        distributorImpl = new Distributor();
        distributor = Distributor(deployUUPS(address(distributorImpl), hex""));
        distributor.initialize(ICore(address(coreBorrow)));

        vm.startPrank(governor);
        distributor.setDisputeAmount(1e18);
        distributor.setDisputePeriod(1 days);
        distributor.setDisputeToken(angle);
        vm.stopPrank();

        angle.mint(address(alice), 100e18);

        Claim[4] memory transactions = [
            Claim({user: alice, token: address(angle), amount: 1e18}),
            Claim({user: bob, token: address(angle), amount: 10e18}),
            Claim({user: charlie, token: address(angle), amount: 3e18}),
            Claim({user: dylan, token: address(angle), amount: 2e18})
        ];

        for (uint i = 0; i < transactions.length; i++) {
            hashes.push(keccak256(abi.encodePacked(transactions[i].user, transactions[i].token, transactions[i].amount)));
        }

        uint n = transactions.length;
        uint offset = 0;

        while (n > 0) {
            for (uint i = 0; i < n - 1; i += 2) {
                hashes.push(
                    keccak256(
                        abi.encodePacked(hashes[offset + i], hashes[offset + i + 1])
                    )
                );
            }
            offset += n;
            n = n / 2;
        }
    }

    function getRoot() public view returns (bytes32) {
        return hashes[hashes.length - 1];
    }
}

contract Test_Distributor_Initialize is DistributorCreatorTest {
    Distributor d;

    function setUp() public override {
        super.setUp();
        d = Distributor(deployUUPS(address(new Distributor()), hex""));
    }

    function test_RevertWhen_CalledOnImplem() public {
        vm.expectRevert("Initializable: contract is already initialized");
        distributorImpl.initialize(ICore(address(0)));
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        d.initialize(ICore(address(0)));
    }

    function test_Success() public {
        d.initialize(ICore(address(coreBorrow)));

        assertEq(address(coreBorrow), address(d.core()));
    }
}

contract Test_Distributor_toggleTrusted is DistributorCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(NotGovernor.selector);
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

contract Test_Distributor_toggleOperator is DistributorCreatorTest {
    function test_RevertWhen_NotTrusted() public {
        vm.expectRevert(NotTrusted.selector);
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

contract Test_Distributor_toggleOnlyOperatorCanClaim is DistributorCreatorTest {
    function test_RevertWhen_NotTrusted() public {
        vm.expectRevert(NotTrusted.selector);
        distributor.toggleOnlyOperatorCanClaim(bob);
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.toggleOnlyOperatorCanClaim(bob);
        assertEq(distributor.onlyOperatorCanClaim(bob), 1);

        vm.prank(bob);
        distributor.toggleOnlyOperatorCanClaim(bob);
        assertEq(distributor.onlyOperatorCanClaim(bob), 0);
    }
}

contract Test_Distributor_recoverERC20 is DistributorCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(NotGovernor.selector);
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

contract Test_Distributor_setDisputePeriod is DistributorCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(NotGovernor.selector);
        distributor.setDisputePeriod(0);
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.setDisputePeriod(1);
        assertEq(distributor.disputePeriod(), 1);
    }
}

contract Test_Distributor_setDisputeToken is DistributorCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(NotGovernor.selector);
        distributor.setDisputeToken(angle);
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.setDisputeToken(angle);
        assertEq(address(distributor.disputeToken()), address(0));
    }
}

contract Test_Distributor_setDisputeAmount is DistributorCreatorTest {
    function test_RevertWhen_NotGovernor() public {
        vm.expectRevert(NotGovernor.selector);
        distributor.setDisputeAmount(0);
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.setDisputeAmount(1);
        assertEq(distributor.disputeAmount(), 1);
    }
}

contract Test_Distributor_updateTree is DistributorCreatorTest {
    function test_RevertWhen_NotTrusted() public {
        vm.expectRevert(NotTrusted.selector);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));
    }

    function test_RevertWhen_DisputeOngoing() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.expectRevert(NotTrusted.selector);
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));
    }

    function test_RevertWhen_DisputeNotFinished() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.warp(distributor.endOfDisputePeriod() + 1);

        vm.expectRevert(NotTrusted.selector);
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

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
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HAS")}));

        (merkleRoot, ipfsHash) = distributor.lastTree();
        assertEq(merkleRoot, getRoot());
        assertEq(ipfsHash, keccak256("IPFS_HASH"));
    }
}

contract Test_Distributor_revokeTree is DistributorCreatorTest {
    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        vm.expectRevert(NotGovernorOrGuardian.selector);
        distributor.revokeTree();
    }

    function test_RevertWhen_UnresolvedDispute() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.expectRevert(UnresolvedDispute.selector);
        vm.prank(governor);
        distributor.revokeTree();
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        vm.prank(governor);
        distributor.revokeTree();

        (bytes32 merkleRoot, bytes32 ipfsHash) = distributor.tree();
        (bytes32 lastMerkleRoot, bytes32 lastIpfsHash) = distributor.lastTree();

        assertEq(merkleRoot, lastMerkleRoot);
        assertEq(ipfsHash, lastIpfsHash);
        assertEq(distributor.endOfDisputePeriod(), 0);
    }
}

contract Test_Distributor_disputeTree is DistributorCreatorTest {
    function test_RevertWhen_UnresolvedDispute() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        vm.expectRevert(UnresolvedDispute.selector);
        vm.prank(governor);
        distributor.disputeTree("wrong");
    }

    function test_RevertWhen_InvalidDispute() public {
        vm.expectRevert(InvalidDispute.selector);
        vm.prank(governor);
        distributor.disputeTree("wrong");
    }

    function test_Success() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        vm.warp(distributor.endOfDisputePeriod() - 1);
        vm.startPrank(alice);
        angle.approve(address(distributor), distributor.disputeAmount());
        distributor.disputeTree("wrong");
        vm.stopPrank();

        assertEq(distributor.disputer(), address(alice));
    }
}

contract Test_Distributor_resolveDispute is DistributorCreatorTest {
    function test_RevertWhen_NotGovernorOrGuardian() public {
        vm.expectRevert(NotGovernorOrGuardian.selector);
        distributor.resolveDispute(true);
    }

    function test_RevertWhen_NoDispute() public {
        vm.expectRevert(NoDispute.selector);
        vm.prank(governor);
        distributor.resolveDispute(true);
    }

    function test_SuccessValid() public {
        vm.prank(governor);
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

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
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

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

/*
contract Test_Distributor_claim is DistributorCreatorTest {
    function test_RevertWhen_NotWhitelisted() public {
        bytes32[] memory proofs = new bytes32[](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = hashes[0];
        users[0] = bob;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        vm.expectRevert(NotWhitelisted.selector);
        distributor.claim(users, tokens, amounts, proofs);
    }

    function test_RevertWhen_InvalidProof() public {
        bytes32[] memory proofs = new bytes32[](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = "0x";
        users[0] = bob;
        tokens[0] = address(angle);
        amounts[0] = 1e18;

        vm.expectRevert(InvalidProof.selector);
        distributor.claim(users, tokens, amounts, proofs);
    }

    function test_Success() public {
        distributor.updateTree(MerkleTree({merkleRoot: getRoot(), ipfsHash: keccak256("IPFS_HASH")}));

        bytes32[] memory proofs = new bytes32[](1);
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        proofs[0] = hashes[0];
        users[0] = bob;
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        uint256 balance = angle.balanceOf(address(bob));
        distributor.claim(users, tokens, amounts, proofs);
        assertEq(angle.balanceOf(address(bob)), balance + 1e18);
    }
}
*/