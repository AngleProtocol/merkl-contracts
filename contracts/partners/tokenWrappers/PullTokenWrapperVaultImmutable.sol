// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title PullTokenWrapperVaultImmutable
/// @notice Non-upgradeable wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev In this version of the PullTokenWrapper, tokens are pulled from a holder address during claims,
/// then deposited into an ERC4626 vault on behalf of the recipient
/// @dev Managers of such wrapper contracts must ensure that the holder address has enough allowance to the wrapper
/// contract for the token pulled during claims
contract PullTokenWrapperVaultImmutable is PullTokenWrapperImmutableBase {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice ERC4626 vault into which claimed tokens are deposited
    address public immutable vault;

    // ================================= CONSTRUCTOR =================================

    constructor(
        address _token,
        address _distributionCreator,
        address _holder,
        address _vault
    )
        ERC20(string(abi.encodePacked(IERC20Metadata(_token).name(), " (wrapped)")), IERC20Metadata(_token).symbol())
        PullTokenWrapperImmutableBase(_token, _distributionCreator, _holder)
    {
        if (_vault == address(0)) revert Errors.ZeroAddress();
        vault = _vault;
        // Max-approve the vault once so deposits don't need per-tx approvals
        IERC20(_token).safeApprove(_vault, type(uint256).max);
    }

    // ================================= FUNCTIONS =================================

    /// @notice Hook called before every transfer: pulls underlying tokens from the holder and deposits them
    /// into the ERC4626 vault on behalf of the recipient when the transfer originates from the distributor
    /// (claim) or is directed to the fee recipient
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == distributor || to == feeRecipient) {
            IERC20(token).safeTransferFrom(holder, address(this), amount);
            IERC4626(vault).deposit(amount, to);
        }
    }

    /// @notice Resets the token allowance granted to the vault (e.g. after a vault migration or if the
    /// allowance has been partially consumed by a non-standard vault)
    /// @param _allowance New allowance to set
    function setVaultAllowance(uint256 _allowance) external onlyHolderOrGovernor {
        IERC20(token).safeApprove(vault, 0);
        IERC20(token).safeApprove(vault, _allowance);
    }
}
