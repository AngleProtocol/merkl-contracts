// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { AccessControlManager } from "../contracts/AccessControlManager.sol";
import { Disputer } from "../contracts/Disputer.sol";
import { Distributor } from "../contracts/Distributor.sol";
import { DistributionCreator } from "../contracts/DistributionCreator.sol";
import { MockToken } from "../contracts/mock/MockToken.sol";

// Usage (defaults: angleLabs = TEMP_GOVERNOR, deployer = GUARDIAN_ADDRESS):
// forge script scripts/verifyMerklDeployment.s.sol \
//     --sig "run(address,address,address,address,address,address)" \
//     <proxyAdmin> <accessControlManager> <distributor> <distributionCreator> <aglaMerkl> <disputer> \
//     --rpc-url $RPC_URL
//
// Or with explicit angleLabs / deployer (use address(0) to fall back to defaults):
// forge script scripts/verifyMerklDeployment.s.sol \
//     --sig "run(address,address,address,address,address,address,address,address)" \
//     <proxyAdmin> <accessControlManager> <distributor> <distributionCreator> <aglaMerkl> <disputer> \
//     <angleLabs> <deployer> \
//     --rpc-url $RPC_URL
contract VerifyMerklDeployment is Script {
    address public constant KEEPER = 0x435046800Fb9149eE65159721A92cB7d50a7534b;
    address public constant DUMPER = 0xeaC6A75e19beB1283352d24c0311De865a867DAB;
    address public constant TEMP_GOVERNOR = 0xb08AB4332AD871F89da24df4751968A61e58013c;
    address public constant GUARDIAN_ADDRESS = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;
    address public constant EXPECTED_MERKL_DEPLOYER_ADDRESS = 0x9f76a95AA7535bb0893cf88A146396e00ed21A12;

    address[3] public DISPUTER_WHITELIST = [
        0xeA05F9001FbDeA6d4280879f283Ff9D0b282060e,
        0x0dd2Ea40A3561C309C03B96108e78d06E8A1a99B,
        0xF4c94b2FdC2efA4ad4b831f312E7eF74890705DA
    ];

    bytes32 private constant IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    bytes32 private constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    uint256 private failures;
    uint256 private warnings;

    address private angleLabs;
    address private deployer;

    function run(
        address proxyAdmin,
        address accessControlManager,
        address distributor,
        address distributionCreator,
        address aglaMerkl,
        address disputer
    ) external {
        _run(proxyAdmin, accessControlManager, distributor, distributionCreator, aglaMerkl, disputer, address(0), address(0));
    }

    function run(
        address proxyAdmin,
        address accessControlManager,
        address distributor,
        address distributionCreator,
        address aglaMerkl,
        address disputer,
        address _angleLabs,
        address _deployer
    ) external {
        _run(proxyAdmin, accessControlManager, distributor, distributionCreator, aglaMerkl, disputer, _angleLabs, _deployer);
    }

    function _run(
        address proxyAdmin,
        address accessControlManager,
        address distributor,
        address distributionCreator,
        address aglaMerkl,
        address disputer,
        address _angleLabs,
        address _deployer
    ) internal {
        angleLabs = _angleLabs == address(0) ? TEMP_GOVERNOR : _angleLabs;
        deployer = _deployer == address(0) ? GUARDIAN_ADDRESS : _deployer;

        console.log("\n========== Verifying Merkl Deployment ==========");
        console.log("Chain ID:", block.chainid);
        console.log("Expected angleLabs:", angleLabs);
        console.log("Expected deployer:", deployer);

        checkProxyAdmin(proxyAdmin, accessControlManager);
        checkAccessControlManager(accessControlManager);
        checkAglaMerkl(aglaMerkl);
        checkDistributor(distributor, accessControlManager, aglaMerkl);
        checkDistributionCreator(distributionCreator, accessControlManager, distributor, aglaMerkl);
        checkDisputer(disputer, distributor);
        checkMerklDeployerNonces(distributor, distributionCreator);

        console.log("\n========== Summary ==========");
        console.log("Failures:", failures);
        console.log("Warnings:", warnings);
        if (failures > 0) revert("Verification failed");
        console.log("All checks passed");
    }

    function checkProxyAdmin(address proxyAdmin, address acmProxy) internal {
        console.log("\n--- ProxyAdmin ---");
        ProxyAdmin pa = ProxyAdmin(proxyAdmin);

        _expectEq(pa.owner(), angleLabs, "ProxyAdmin owner == angleLabs");

        address acmAdmin = address(uint160(uint256(vm.load(acmProxy, ADMIN_SLOT))));
        _expectEq(acmAdmin, proxyAdmin, "AccessControlManager proxy admin == ProxyAdmin");
    }

    function checkAccessControlManager(address acm) internal {
        console.log("\n--- AccessControlManager ---");
        AccessControlManager m = AccessControlManager(acm);

        _expect(m.isGovernor(angleLabs), "angleLabs is governor");
        _expectNot(m.isGovernor(deployer) && deployer != angleLabs, "deployer is NOT governor");

        uint256 governorCount = m.getRoleMemberCount(m.GOVERNOR_ROLE());
        _expectEqUint(governorCount, 1, "governor count == 1");
    }

    function checkAglaMerkl(address aglaMerkl) internal {
        console.log("\n--- AglaMerkl ---");
        MockToken t = MockToken(aglaMerkl);

        string memory name = t.name();
        string memory sym = t.symbol();
        uint8 dec = t.decimals();
        console.log("Name:", name);
        console.log("Symbol:", sym);
        console.log("Decimals:", dec);

        _expect(keccak256(bytes(name)) == keccak256(bytes("aglaMerkl")), "Name == aglaMerkl");
        _expect(keccak256(bytes(sym)) == keccak256(bytes("aglaMerkl")), "Symbol == aglaMerkl");
        _expectEqUint(uint256(dec), 6, "Decimals == 6");
    }

    function checkDistributor(address distributor, address acm, address aglaMerkl) internal {
        console.log("\n--- Distributor ---");
        Distributor d = Distributor(distributor);

        _expectImplDeployed(distributor, "Distributor");
        _expectEq(address(d.accessControlManager()), acm, "accessControlManager wired");
        _expectEqUint(d.disputePeriod(), 1, "disputePeriod == 1");
        _expectEqUint(d.canUpdateMerkleRoot(KEEPER), 1, "KEEPER is trusted");
        _expectEqUint(d.canUpdateMerkleRoot(deployer), 0, "deployer is NOT trusted");

        address dt = address(d.disputeToken());
        console.log("disputeToken:", dt);
        if (dt == address(0)) {
            _warn("disputeToken not set (default deploy path)");
        } else {
            _checkDisputeAmount(d, dt, aglaMerkl);
        }
    }

    function _checkDisputeAmount(Distributor d, address dt, address aglaMerkl) internal {
        string memory symbol = MockToken(dt).symbol();
        uint8 decimals = MockToken(dt).decimals();
        uint256 amount = d.disputeAmount();
        console.log("disputeToken symbol:", symbol);
        console.log("disputeAmount:", amount);

        bytes32 sh = keccak256(bytes(symbol));
        if (sh == keccak256(bytes("EURA")) || sh == keccak256(bytes("USDC")) || sh == keccak256(bytes("USDT"))) {
            _expectEqUint(amount, 100 * 10 ** decimals, "disputeAmount == 100 stables");
        } else if (sh == keccak256(bytes("WETH"))) {
            _expectEqUint(amount, 3 * 10 ** (uint256(decimals) - 2), "disputeAmount == 0.03 WETH");
        } else if (dt == aglaMerkl) {
            _warn("disputeToken is aglaMerkl - disputeAmount not configured by deploy script");
        } else {
            _warn("disputeToken symbol not recognized - skipping disputeAmount check");
        }
    }

    function checkDistributionCreator(address distributionCreator, address acm, address distributor, address aglaMerkl) internal {
        console.log("\n--- DistributionCreator ---");
        DistributionCreator c = DistributionCreator(distributionCreator);

        _expectImplDeployed(distributionCreator, "DistributionCreator");
        _expectEq(address(c.accessControlManager()), acm, "accessControlManager wired");
        _expectEq(c.distributor(), distributor, "distributor wired");
        _expectEq(c.feeRecipient(), DUMPER, "feeRecipient == DUMPER");
        _expectEqUint(c.defaultFees(), 0.03 gwei, "defaultFees == 0.03 gwei");
        _expectEqUint(c.campaignSpecificFees(4), 5 * 1e6, "campaignSpecificFees[4] == 5%");
        _expectEqUint(c.rewardTokenMinAmounts(aglaMerkl), 1, "rewardTokenMinAmounts[aglaMerkl] == 1");
        _expect(bytes(c.message()).length > 0, "message is set");
    }

    function checkDisputer(address disputer, address distributor) internal {
        console.log("\n--- Disputer ---");
        if (disputer == address(0)) {
            _warn("Disputer address is zero, skipping checks");
            return;
        }
        Disputer d = Disputer(disputer);

        _expectEq(d.owner(), angleLabs, "Disputer owner == angleLabs");
        _expectEq(address(d.distributor()), distributor, "distributor wired");

        address dt = address(Distributor(distributor).disputeToken());
        if (dt != address(0)) {
            uint256 bal = MockToken(dt).balanceOf(disputer);
            uint256 expected = 200 * 10 ** MockToken(dt).decimals();
            console.log("disputeToken balance:", bal);
            if (bal < expected) _warn("Disputer balance below 200 dispute tokens");
        } else {
            _warn("disputeToken not set on Distributor, skipping Disputer balance check");
        }

        for (uint256 i = 0; i < DISPUTER_WHITELIST.length; i++) {
            _expect(d.whitelist(DISPUTER_WHITELIST[i]), "whitelist entry present");
        }
    }

    // Deploy script nonces on the Merkl deployer:
    //   0 -> Distributor implementation
    //   1 -> Distributor proxy
    //   2 -> initialize (no deployment)
    //   3 -> DistributionCreator implementation
    //   4 -> DistributionCreator proxy
    function checkMerklDeployerNonces(address distributor, address distributionCreator) internal {
        console.log("\n--- Merkl deployer nonce-derived addresses ---");

        address expectedDistribImpl = vm.computeCreateAddress(EXPECTED_MERKL_DEPLOYER_ADDRESS, 0);
        address expectedDistribProxy = vm.computeCreateAddress(EXPECTED_MERKL_DEPLOYER_ADDRESS, 1);
        address expectedCreatorImpl = vm.computeCreateAddress(EXPECTED_MERKL_DEPLOYER_ADDRESS, 3);
        address expectedCreatorProxy = vm.computeCreateAddress(EXPECTED_MERKL_DEPLOYER_ADDRESS, 4);

        _expectEq(distributor, expectedDistribProxy, "Distributor proxy at Merkl deployer nonce 1");
        _expectEq(distributionCreator, expectedCreatorProxy, "DistributionCreator proxy at Merkl deployer nonce 4");

        address actualDistribImpl = address(uint160(uint256(vm.load(distributor, IMPL_SLOT))));
        address actualCreatorImpl = address(uint160(uint256(vm.load(distributionCreator, IMPL_SLOT))));
        _expectEq(actualDistribImpl, expectedDistribImpl, "Distributor impl at Merkl deployer nonce 0");
        _expectEq(actualCreatorImpl, expectedCreatorImpl, "DistributionCreator impl at Merkl deployer nonce 3");
    }

    function _expectImplDeployed(address proxy, string memory label) internal {
        address impl = address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
        if (impl == address(0)) {
            _fail(string.concat(label, " impl slot is zero"));
            return;
        }
        if (impl.code.length == 0) {
            _fail(string.concat(label, " impl has no code"));
            return;
        }
        console.log(string.concat("[OK] ", label, " impl deployed at"), impl);
    }

    function _expect(bool condition, string memory label) internal {
        if (condition) console.log("[OK]", label);
        else _fail(label);
    }

    function _expectNot(bool condition, string memory label) internal {
        if (!condition) console.log("[OK]", label);
        else _fail(label);
    }

    function _expectEq(address a, address b, string memory label) internal {
        if (a == b) {
            console.log("[OK]", label);
        } else {
            console.log("[FAIL]", label);
            console.log("  actual:  ", a);
            console.log("  expected:", b);
            failures++;
        }
    }

    function _expectEqUint(uint256 a, uint256 b, string memory label) internal {
        if (a == b) {
            console.log("[OK]", label);
        } else {
            console.log("[FAIL]", label);
            console.log("  actual:  ", a);
            console.log("  expected:", b);
            failures++;
        }
    }

    function _fail(string memory label) internal {
        console.log("[FAIL]", label);
        failures++;
    }

    function _warn(string memory label) internal {
        console.log("[WARN]", label);
        warnings++;
    }
}
