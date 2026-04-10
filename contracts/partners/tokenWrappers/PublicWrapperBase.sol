// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";

/// @title PublicWrapperBase
/// @notice Abstract base for permissionless wrappers where anyone can mint by providing underlying tokens
/// @dev Handles the common mint path (transferFrom underlying + mint wrapper tokens on the fly) and
/// the afterTokenTransfer burn logic. Child contracts only need to implement `_onClaim` to define
/// what happens when tokens are claimed from the distributor.
abstract contract PublicWrapperBase is PullTokenWrapperImmutableBase {
    using SafeERC20 for IERC20;

    /// @dev Flag to prevent _afterTokenTransfer from burning during internal mints
    uint256 private _minting;

    /// @notice Signals to frontends that 2 approvals are needed (one for the wrapper, one for the underlying)
    function isTokenWrapper() external pure returns (bool) {
        return true;
    }

    /// @notice Hook called before every transfer
    /// @dev - When transferring TO the distributor: pulls underlying from sender and mints wrapper tokens
    /// @dev - When transferring TO the feeRecipient: pulls underlying to fee recipient and mints wrapper tokens
    /// @dev - When transferring FROM the distributor (claim): delegates to `_onClaim`
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Mint path: anyone can send to the distributor by providing underlying tokens
        if (to == distributor) {
            IERC20(token).safeTransferFrom(from, address(this), amount);
            _minting = 1;
            _mint(from, amount);
            _minting = 0;
        }

        // Merkl protocol fee path: underlying goes directly to fee recipient
        if (to == feeRecipient) {
            IERC20(token).safeTransferFrom(from, feeRecipient, amount);
            _minting = 1;
            _mint(from, amount);
            _minting = 0;
        }

        // Claim path: child contract defines the behavior
        if (from == distributor) {
            _onClaim(to, amount);
        }
    }

    /// @notice Skips burn during internal mints so the sender can temporarily hold wrapper tokens
    function _afterTokenTransfer(address, address to, uint256 amount) internal override {
        if (_minting == 0 && isAllowed[to] == 0) _burn(to, amount);
    }

    /// @notice Disabled: minting happens automatically in `_beforeTokenTransfer`
    function mint(address, uint256) external override {}

    /// @notice Burns wrapper tokens from a given address
    function burn(address from, uint256 amount) external onlyHolderOrGovernor {
        _burn(from, amount);
    }

    /// @notice Called when tokens are claimed from the distributor
    /// @dev Must be implemented by child contracts to define claim behavior
    /// @param to The address receiving the claim
    /// @param amount The amount being claimed
    function _onClaim(address to, uint256 amount) internal virtual;
}
