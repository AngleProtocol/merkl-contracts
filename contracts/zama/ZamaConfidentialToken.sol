// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC7984 } from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { FHE, euint64 } from "@fhevm/solidity/lib/FHE.sol";

/// @title ZamaConfidentialToken
/// @author Merkl SAS
/// @notice A genuine ERC-7984 confidential token, wired to Zama's real fhEVM coprocessor via
/// {ZamaEthereumConfig} (Ethereum mainnet, Sepolia, and the local fhevm devnet -- see that contract for the
/// exact chain-id dispatch and addresses). Amounts are true ciphertexts computed by the real coprocessor and
/// gated by the real ACL: there is no plaintext shortcut and no test double standing in for the coprocessor
/// or the ACL. A mock token once existed alongside this one and was dropped deliberately — it required a
/// mainnet fork anyway (to reach the real ACL), so it added a second contract to keep in sync with a spec
/// while buying nothing this one cannot do.
/// @dev Inherits {ERC7984-_update} unchanged. That function is what makes a pre-delegation transfer's
/// ciphertext handle stay decryptable after a later delegation: it grants PERSISTENT allowances
/// (`FHE.allow(transferred, from)`, `FHE.allow(transferred, to)`, `FHE.allowThis(transferred)`) rather than
/// transient ones, so the handle remains in the ACL's `persistedAllowedPairs` regardless of when a holder
/// later calls `delegateForUserDecryption`.
contract ZamaConfidentialToken is ERC7984, ZamaEthereumConfig, Ownable {
    constructor(
        string memory name_,
        string memory symbol_,
        string memory contractURI_,
        address owner_
    ) ERC7984(name_, symbol_, contractURI_) Ownable(owner_) {}

    /// @inheritdoc ERC7984
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mints `amount` to `to`.
    /// @dev Uses `FHE.asEuint64`, a trivial ON-CHAIN encryption of a plaintext `uint64` into a ciphertext
    /// handle -- no client-side encrypted input or relayer-issued proof is needed. A trivially-encrypted
    /// value is only as confidential as the calldata that produced it, so this entry point is owner-gated:
    /// it exists to seed balances for the delegation experiment, not to move value confidentially.
    function mint(address to, uint64 amount) external onlyOwner returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount));
    }
}
