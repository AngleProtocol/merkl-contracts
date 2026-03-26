// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PublicWrapperBase } from "./PublicWrapperBase.sol";
import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title ClaimFeeTokenWrapperImmutable
/// @notice Non-upgradeable wrapper that charges a configurable fee on claims
contract ClaimFeeTokenWrapperImmutable is PublicWrapperBase {
    using SafeERC20 for IERC20;

    uint256 public constant BASE = 1e9;

    /// @notice Fee rate applied on claims, in BASE units (e.g. 1e7 = 1%)
    uint256 public claimFeeRate;
    /// @notice Address receiving the claim fees
    address public claimFeeRecipient;

    event ClaimFeeRateUpdated(uint256 newClaimFeeRate);
    event ClaimFeeRecipientUpdated(address indexed newClaimFeeRecipient);

    constructor(
        address _token,
        address _distributionCreator,
        address _holder,
        uint256 _claimFeeRate,
        address _claimFeeRecipient
    )
        ERC20(string(abi.encodePacked(IERC20Metadata(_token).name(), " (wrapped)")), IERC20Metadata(_token).symbol())
        PullTokenWrapperImmutableBase(_token, _distributionCreator, _holder)
    {
        if (_claimFeeRate >= BASE) revert Errors.InvalidParam();
        if (_claimFeeRecipient == address(0)) revert Errors.ZeroAddress();
        claimFeeRate = _claimFeeRate;
        claimFeeRecipient = _claimFeeRecipient;
    }

    /// @notice On claim: charges a fee and sends the rest to the claimer
    function _onClaim(address to, uint256 amount) internal override {
        uint256 feeAmount = (amount * claimFeeRate) / BASE;
        if (feeAmount > 0) IERC20(token).safeTransfer(claimFeeRecipient, feeAmount);
        IERC20(token).safeTransfer(to, amount - feeAmount);
    }

    // ================================= ADMIN =================================

    /// @notice Updates the claim fee rate
    function setClaimFeeRate(uint256 _claimFeeRate) external onlyHolderOrGovernor {
        if (_claimFeeRate >= BASE) revert Errors.InvalidParam();
        claimFeeRate = _claimFeeRate;
        emit ClaimFeeRateUpdated(_claimFeeRate);
    }

    /// @notice Updates the claim fee recipient
    function setClaimFeeRecipient(address _claimFeeRecipient) external onlyHolderOrGovernor {
        if (_claimFeeRecipient == address(0)) revert Errors.ZeroAddress();
        claimFeeRecipient = _claimFeeRecipient;
        emit ClaimFeeRecipientUpdated(_claimFeeRecipient);
    }
}
