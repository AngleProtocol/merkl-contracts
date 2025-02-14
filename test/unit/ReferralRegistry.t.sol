// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../../contracts/ReferralRegistry.sol";
import "../../contracts/interfaces/IAccessControlManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


contract ReferralRegistryTest is Test {
    ReferralRegistry referralRegistry;
    ReferralRegistry referralRegistryImple;
    IAccessControlManager accessControlManager;
    address paymentToken;

    address owner = vm.addr(1);
    address user = vm.addr(2);
    address referrer = vm.addr(3);
    address feeRecipient = vm.addr(4);

    string referralKey = "testKey";
    uint256 cost = 1000;
    uint256 feeSetup = 100;
    bool requiresRefererToBeSet = true;
    bool requiresAuthorization = false;

    function deployUUPS(address implementation, bytes memory data) public returns (address) {
        return address(new ERC1967Proxy(implementation, data));
    }

    function setUp() public {
        accessControlManager = IAccessControlManager(address(new MockAccessControlManager()));
        referralRegistryImple = new ReferralRegistry();
        paymentToken = address(new MockERC20());
        referralRegistry =  ReferralRegistry(payable(deployUUPS(address(referralRegistryImple), hex"")));
        referralRegistry.initialize(accessControlManager, feeSetup, feeRecipient);
    }

    function testAddReferralKeyCostZero() public {
        vm.prank(owner);
        referralRegistry.setCostReferralProgram(0);
        referralRegistry.addReferralKey(referralKey, cost, requiresRefererToBeSet, owner, requiresAuthorization, paymentToken);

        ReferralRegistry.ReferralProgram memory program = referralRegistry.getReferralProgram(referralKey);
        assertEq(program.owner, owner);
        assertEq(program.cost, cost);
        assertEq(program.requiresRefererToBeSet, requiresRefererToBeSet);
        assertEq(program.requiresAuthorization, requiresAuthorization);
        assertEq(address(program.paymentToken), address(paymentToken));
    }

    function testAddReferralKey() public {
        vm.prank(owner);
        uint256 fee = referralRegistry.costReferralProgram();
        referralRegistry.addReferralKey{value: fee}(referralKey, cost, requiresRefererToBeSet, owner, requiresAuthorization, paymentToken);

        ReferralRegistry.ReferralProgram memory program = referralRegistry.getReferralProgram(referralKey);
        assertEq(program.owner, owner);
        assertEq(program.cost, cost);
        assertEq(program.requiresRefererToBeSet, requiresRefererToBeSet);
        assertEq(program.requiresAuthorization, requiresAuthorization);
        assertEq(address(program.paymentToken), address(paymentToken));
    }

    function testEditReferralProgram() public {
        vm.prank(owner);
        uint256 fee = referralRegistry.costReferralProgram();

        referralRegistry.addReferralKey{value: fee}(referralKey, cost, requiresRefererToBeSet, owner, requiresAuthorization, paymentToken);

        uint256 newCost = 2000;
        bool newRequiresRefererToBeSet = false;
        bool newRequiresAuthorization = false;
        address newPaymentToken = address(new MockERC20());

        vm.prank(owner);
        referralRegistry.editReferralProgram(referralKey, newCost, newRequiresAuthorization, newRequiresRefererToBeSet, newPaymentToken);

        ReferralRegistry.ReferralProgram memory program = referralRegistry.getReferralProgram(referralKey);
        assertEq(program.cost, newCost);
        assertEq(program.requiresRefererToBeSet, newRequiresRefererToBeSet);
        assertEq(program.requiresAuthorization, newRequiresAuthorization);
        assertEq(address(program.paymentToken), address(newPaymentToken));
    }

    function testBecomeReferrer() public {
        vm.prank(owner);
        uint256 fee = referralRegistry.costReferralProgram();

        referralRegistry.addReferralKey{value: fee}(referralKey, cost, requiresRefererToBeSet, owner, requiresAuthorization, paymentToken);

        string memory referrerCode = "referrerCode";
        vm.startPrank(referrer);
        IERC20(paymentToken).approve(address(referralRegistry), cost);
        referralRegistry.becomeReferrer(referralKey, referrerCode);

        ReferralRegistry.ReferralStatus status = referralRegistry.getReferrerStatus(referralKey, referrer);
        assertEq(uint(status), uint(ReferralRegistry.ReferralStatus.Set));

        string memory storedReferrerCode = referralRegistry.referrerCodeMapping(referralKey, referrer);
        assertEq(storedReferrerCode, referrerCode);

        address storedReferrer = referralRegistry.codeToReferrer(referralKey, referrerCode);
        assertEq(storedReferrer, referrer);
    }

    function testAcknowledgeReferrer() public {
        vm.prank(owner);
        uint256 fee = referralRegistry.costReferralProgram();

        referralRegistry.addReferralKey{value: fee}(referralKey, cost, requiresRefererToBeSet, owner, requiresAuthorization, paymentToken);

        string memory referrerCode = "referrerCode";
        vm.startPrank(referrer);
        IERC20(paymentToken).approve(address(referralRegistry), cost);
        referralRegistry.becomeReferrer(referralKey, referrerCode);
        vm.stopPrank();
        vm.prank(user);
        referralRegistry.acknowledgeReferrer(referralKey, referrer);

        address referrerOnChain = referralRegistry.getReferrer(referralKey, user);
        assertEq(referrer, referrerOnChain);
    }

    function testAcknowledgeReferrerByKey() public {
        vm.prank(owner);
        uint256 fee = referralRegistry.costReferralProgram();

        referralRegistry.addReferralKey{value: fee}(referralKey, cost, requiresRefererToBeSet, owner, requiresAuthorization, paymentToken);

        string memory referrerCode = "referrerCode";
        vm.startPrank(referrer);
        IERC20(paymentToken).approve(address(referralRegistry), cost);
        referralRegistry.becomeReferrer(referralKey, referrerCode);
        vm.stopPrank();
        vm.prank(user);
        referralRegistry.acknowledgeReferrerByKey(referralKey, referrerCode);

        address referrerOnChain = referralRegistry.getReferrer(referralKey, user);
        assertEq(referrer, referrerOnChain);
    }

    function testAcknowledgeReferrerByKeyWithoutCost() public {
        vm.prank(owner);
        uint256 fee = referralRegistry.costReferralProgram();
        referralRegistry.addReferralKey{value: fee}(referralKey, 0, false, owner, false, address(0));

        string memory referrerCode = "referrerCode";
        vm.startPrank(referrer);
        referralRegistry.becomeReferrer(referralKey, referrerCode);
        vm.stopPrank();
        vm.prank(user);
        referralRegistry.acknowledgeReferrerByKey(referralKey, referrerCode);

        address referrerOnChain = referralRegistry.getReferrer(referralKey, user);
        assertEq(referrer, referrerOnChain);
    }
}

contract MockAccessControlManager is IAccessControlManager {
    function isGovernor(address) external pure returns (bool) {
        return true;
    }

    function isGovernorOrGuardian(address) external pure returns (bool) {
        return true;
    }
}

contract MockERC20 is IERC20 {
    function totalSupply() external pure returns (uint256) {
        return 1000000;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 1000000;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 1000000;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function name() external pure returns (string memory) {
        return "MockERC20";
    }

    function symbol() external pure returns (string memory) {
        return "MERC20";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
