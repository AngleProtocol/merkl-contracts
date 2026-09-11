// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { console } from "forge-std/console.sol";
import { euint64 } from "@fhevm/solidity/lib/FHE.sol";

import { BaseScript } from "../utils/Base.s.sol";
import { ZamaConfidentialToken } from "../../contracts/zama/ZamaConfidentialToken.sol";

/// @notice The delegation surface these scripts drive, with the GENUINE fhevm ACL's signatures. Mind the word
/// order: the CONTRACT's functions are `revokeDelegationForUserDecryption` and
/// `getUserDecryptionDelegationExpirationDate`, whereas the `FHE` library's helpers invert them — reading the
/// library's names off the docs and assuming the contract matches is a mistake that has already been made
/// here once. Every selector below was verified present in the deployed mainnet implementation
/// (`0xcA2E8f1F656CD25C01F05d0b243Ab1ecd4a8ffb6`), not inferred from documentation.
interface IZamaACL {
    function delegateForUserDecryption(address delegate, address contractAddress, uint64 expirationDate) external;

    function revokeDelegationForUserDecryption(address delegate, address contractAddress) external;

    function getUserDecryptionDelegationExpirationDate(
        address delegator,
        address delegate,
        address contractAddress
    ) external view returns (uint64);
}

/// @dev Scripts that deploy and drive a REAL ERC-7984 confidential token (`ZamaConfidentialToken`) against
/// Zama's genuine fhEVM coprocessor and ACL on Ethereum mainnet. These scripts produce real ciphertext
/// handles that the Zama relayer can actually decrypt — the engine-side experiment that does so lives in the
/// monorepo at `apps/engine/scripts/zama-decrypt-experiment.ts`, and goes through the engine's own
/// `zama-decrypt` package rather than calling the Zama SDK directly, so a success is evidence about our own
/// integration and not merely about the SDK.
///
/// Every step signs through {BaseScript}'s standard credential resolution ($DEPLOYER_PRIVATE_KEY /
/// $DEPLOYER_ADDRESS / $MNEMONIC) -- no key or mnemonic is ever derived or held here. The team's two
/// deployers, {DEPLOYER_A} and {DEPLOYER_B}, are named constants for documentation and for the
/// fail-loud checks below; whichever one actually signs is entirely up to how the operator configured
/// those environment variables for a given invocation.
///
/// Scenario: mint to {DEPLOYER_A}, transfer A -> B, and only THEN delegate. The transfer must precede the
/// delegation -- that ordering is the entire point of the experiment (it proves a pre-delegation handle
/// stays decryptable). `Delegate` takes the delegator as a parameter defaulting to {DEPLOYER_A}, so the
/// default flow needs only A's credentials configured; {ERC7984-_update} grants PERSISTENT allowance on the
/// transferred handle to BOTH sides of a transfer, so B is an equally valid delegator when the operator has
/// B's credentials configured instead (pass `delegator` explicitly).
///
/// Run `Deploy`, `Mint`, `Transfer`, then `Delegate` as FOUR SEPARATE `forge script` invocations, in that
/// order -- never combined into one script. `Transfer` and `Delegate` read the caller's current on-chain
/// state (balance handle, delegation status) at simulation time; a single script that broadcasts mint,
/// transfer and delegate together bakes each step's calldata from ONE UPFRONT simulation pass, before any of
/// it is actually mined. The real FHEVMExecutor's handle for a given operation depends on execution context
/// that only exists once that operation is genuinely mined, so a later step's pre-baked calldata (e.g.
/// `confidentialTransfer`'s amount handle, read from a mint that hasn't really happened yet) can reference a
/// handle the real ACL never actually granted -- this was verified empirically: a combined script simulates
/// clean but the broadcasted transfer reverts with `ERC7984UnauthorizedUseOfEncryptedAmount`. Separate
/// invocations don't have this problem because each one simulates fresh against the chain's real state.
///
/// HARD RULE: never run any of these with `--broadcast` against mainnet or any real network -- simulate only
/// (drop `--broadcast`), or broadcast against your own local mainnet fork, impersonating the two deployers
/// (never a private key -- mirrors the repo's `impersonate:script` / `impersonate:setBalance` pattern):
///   anvil --fork-url https://rpc.internal.merkl.xyz/main/evm/1
///   cast rpc anvil_setBalance 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 1000000000000000000
///   cast rpc anvil_setBalance 0x9f76a95AA7535bb0893cf88A146396e00ed21A12 1000000000000000000
///
///   DEPLOYER_ADDRESS=0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 \
///     FOUNDRY_PROFILE=zama forge script scripts/zama/ZamaConfidentialToken.s.sol:Deploy \
///     --rpc-url localhost --unlocked --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast
///   DEPLOYER_ADDRESS=0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 \
///     FOUNDRY_PROFILE=zama forge script scripts/zama/ZamaConfidentialToken.s.sol:Mint \
///     --sig "run(address,address,uint64)" <token> 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 <amount> \
///     --rpc-url localhost --unlocked --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast
///   DEPLOYER_ADDRESS=0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 \
///     FOUNDRY_PROFILE=zama forge script scripts/zama/ZamaConfidentialToken.s.sol:Transfer \
///     --sig "run(address,address)" <token> 0x9f76a95AA7535bb0893cf88A146396e00ed21A12 \
///     --rpc-url localhost --unlocked --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast
///   DEPLOYER_ADDRESS=0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 \
///     FOUNDRY_PROFILE=zama forge script scripts/zama/ZamaConfidentialToken.s.sol:Delegate \
///     --sig "run(address,uint64)" <token> <expiry> \
///     --rpc-url localhost --unlocked --sender 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701 --broadcast
///
/// Real mainnet deployment (run by the user, never by this agent), same four calls with `--rpc-url mainnet`
/// and a real $DEPLOYER_PRIVATE_KEY (or $MNEMONIC) resolved by `op run`, e.g.:
///   FOUNDRY_PROFILE=zama op run --env-file=.env -- forge script scripts/zama/ZamaConfidentialToken.s.sol:Deploy \
///     --rpc-url mainnet --broadcast --verify
contract ZamaConfidentialTokenScript is BaseScript {
    /// @dev The team's primary deployer -- see `impersonate:setBalance` in package.json.
    address internal constant DEPLOYER_A = 0xA9DdD91249DFdd450E81E1c56Ab60E1A62651701;

    /// @dev The team's second deployer.
    address internal constant DEPLOYER_B = 0x9f76a95AA7535bb0893cf88A146396e00ed21A12;

    /// @dev The genuine fhevm ACL on Ethereum mainnet -- present on any mainnet fork, and the only network
    /// {contracts/zama/ZamaConfidentialToken-ZamaEthereumConfig} wires this token's coprocessor to.
    address internal constant MAINNET_ACL = 0xcA2E8f1F656CD25C01F05d0b243Ab1ecd4a8ffb6;

    /// @notice The address the Merkl engine decrypts as — holders grant it `delegateForUserDecryption` on
    /// the ACL, and the engine's `ZAMA_DELEGATE_PRIVATE_KEY` signs the relayer's permits as it. Required,
    /// not derived: an unset or wrong delegate makes the whole pre-delegation-decryption experiment
    /// meaningless, and on a real campaign it silently yields zero rewards.
    /// @dev The canonical Merkl delegate is `0xCE320B9a35aBfD95602B8f272b2730e5633a7337`. Do NOT reuse an
    /// anvil default account here (e.g. `0xf39Fd6...92266`): its private key is public, so anyone could
    /// decrypt the balances of every holder who delegated to it. Those accounts are fine only as throwaway
    /// values on a disposable local fork.
    function _delegate() internal view returns (address delegate) {
        delegate = vm.envOr({ name: "ZAMA_DELEGATE_ADDRESS", defaultValue: address(0) });
        require(delegate != address(0), "ZAMA_DELEGATE_ADDRESS is not set");
    }

    /// @dev Fails loud rather than substituting a test double, and there deliberately is no mock ACL to fall
    /// back to: the ACL is pure bookkeeping with no FHE in it, so a mock could only ever confirm our own
    /// reading of its ABI instead of testing against it.
    function _acl() internal view returns (IZamaACL) {
        require(
            MAINNET_ACL.code.length > 0,
            "Zama ACL has no code on this chain: fork mainnet (anvil --fork-url https://rpc.internal.merkl.xyz/main/evm/1)"
        );
        return IZamaACL(MAINNET_ACL);
    }

    /// @dev Fails loud, before broadcasting, on every invariant the real ACL enforces on
    /// `delegateForUserDecryption` -- `delegator != delegate`, `delegator != contractAddress`, and
    /// `delegate != contractAddress` -- so a misconfiguration surfaces here with a clear message instead of
    /// an opaque ACL revert.
    function _assertDelegationInvariants(address delegator, address delegate, address token) internal pure {
        require(delegator != delegate, "delegator and delegate must differ");
        require(delegator != token, "delegator cannot be the token contract");
        require(delegate != token, "delegate cannot be the token contract");
    }
}

/// @dev Deploys the token with the broadcaster as owner (so a follow-up {Mint} run by the same key succeeds).
contract Deploy is ZamaConfidentialTokenScript {
    /// @dev Mirrors the plaintext `aglaMerkl` test token from `merklDeploy.s.sol` (same name, same
    /// symbol, and {ZamaConfidentialToken-decimals} is already 6 to match) — this is its confidential
    /// counterpart, so the two are recognizable as the same test asset.
    function run() external broadcast returns (ZamaConfidentialToken token) {
        return _run("Confidential aglaMerkl", "caglaMerkl");
    }

    function run(string calldata name, string calldata symbol) external broadcast returns (ZamaConfidentialToken token) {
        return _run(name, symbol);
    }

    function _run(string memory name, string memory symbol) internal returns (ZamaConfidentialToken token) {
        token = new ZamaConfidentialToken(name, symbol, "", broadcaster);
        console.log("ZamaConfidentialToken :", address(token));
        console.log("owner                 :", broadcaster);
        console.log("decimals              :", token.decimals());
        console.log("expected delegate     :", _delegate());
    }
}

/// @dev Owner-gated mint via on-chain trivial encryption -- see {ZamaConfidentialToken-mint}.
contract Mint is ZamaConfidentialTokenScript {
    function run(address token, address to, uint64 amount) external broadcast {
        ZamaConfidentialToken(token).mint(to, amount);
        console.log("minted %s to %s", amount, to);
    }
}

/// @dev Transfers the broadcaster's ENTIRE current balance to `to`. Reuses the caller's own balance handle
/// (which {ERC7984-_update} already allowed them to use) rather than trivially re-encrypting, so this is a
/// genuine `confidentialTransfer`, not an owner-only shortcut.
contract Transfer is ZamaConfidentialTokenScript {
    function run(address token, address to) external broadcast {
        euint64 amount = ZamaConfidentialToken(token).confidentialBalanceOf(broadcaster);
        ZamaConfidentialToken(token).confidentialTransfer(to, amount);
        console.log("transferred entire balance from %s", broadcaster);
        console.log("to:", to);
    }
}

/// @dev Delegates decryption rights for `delegator` to {_delegate}, against the REAL ACL. `delegator` must
/// match the configured broadcaster -- it exists as a parameter (rather than always reading `broadcaster`)
/// so the contract-level scenario note above is enforceable, not just documented: the default overload below
/// pins it to {DEPLOYER_A}, and passing {DEPLOYER_B} explicitly requires the operator to also have
/// configured B's credentials, which the require below checks.
contract Delegate is ZamaConfidentialTokenScript {
    function run(address token, uint64 expiry) external broadcast {
        _run(token, expiry, DEPLOYER_A);
    }

    function run(address token, uint64 expiry, address delegator) external broadcast {
        _run(token, expiry, delegator);
    }

    function _run(address token, uint64 expiry, address delegator) internal {
        require(broadcaster == delegator, "Delegate: configured broadcaster does not match delegator");
        address delegate = _delegate();
        _assertDelegationInvariants(delegator, delegate, token);
        _acl().delegateForUserDecryption(delegate, token, expiry);
        console.log("delegated: holder %s -> delegate %s", delegator, delegate);
        console.log("expiry:", expiry);
    }
}

/// @dev Revokes the broadcaster's delegation, closing the window immediately.
contract Revoke is ZamaConfidentialTokenScript {
    function run(address token) external broadcast {
        _acl().revokeDelegationForUserDecryption(_delegate(), token);
        console.log("revoked for holder:", broadcaster);
    }
}
