// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";

/// @title PullTokenWrapperTransferImmutable
/// @notice Non-upgradeable wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev In this version of the PullTokenWrapper, tokens are pulled directly from the wrapper contract during claims
/// @dev Managers of such wrapper contracts must ensure to transfer enough tokens to the wrapper contract before
/// claims happen
/// @dev This is the non-upgradeable version of `PullTokenWrapperTransfer`
contract PullTokenWrapperTransferImmutable is PullTokenWrapperImmutableBase {
    using SafeERC20 for IERC20;

    constructor(
        address _token,
        address _distributionCreator,
        address _holder
    )
        ERC20(string(abi.encodePacked(IERC20Metadata(_token).name(), " (wrapped)")), IERC20Metadata(_token).symbol())
        PullTokenWrapperImmutableBase(_token, _distributionCreator, _holder)
    {}

    /// @notice Hook called before every transfer: sends underlying tokens from the wrapper contract to the
    /// recipient when the transfer originates from the distributor (claim) or is directed to the fee recipient
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == distributor || to == feeRecipient) IERC20(token).safeTransfer(to, amount);
    }
}
