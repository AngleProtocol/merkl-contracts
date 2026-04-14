// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";
import { Errors } from "../../utils/Errors.sol";

interface IMezoStaking {
    function createLockFor(uint256 _value, uint256 _lockDuration, address _to) external returns (uint256);
}

/// @title MezoWrapper
/// @notice Non-upgradeable wrapper that creates Mezo locks for claimed tokens
/// @dev On claim, underlying tokens are approved and locked via `createLockFor` on the Mezo staking contract
contract MezoWrapper is PullTokenWrapperImmutableBase {
    using SafeERC20 for IERC20;

    /// @notice Mezo staking contract
    address public immutable mezoStaking;
    /// @notice Duration used when creating locks
    uint256 public lockDuration;

    event LockDurationUpdated(uint256 newLockDuration);

    constructor(
        address _token,
        address _distributionCreator,
        address _holder,
        address _mezoStaking,
        uint256 _lockDuration,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) PullTokenWrapperImmutableBase(_token, _distributionCreator, _holder) {
        if (_mezoStaking == address(0)) revert Errors.ZeroAddress();
        mezoStaking = _mezoStaking;
        lockDuration = _lockDuration;
        IERC20(_token).safeApprove(_mezoStaking, type(uint256).max);
    }

    /// @notice Hook called before every transfer: on claim or fee transfer, pulls tokens from holder
    /// and creates a Mezo lock for the recipient
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == distributor || to == feeRecipient) {
            IERC20(token).safeTransferFrom(holder, address(this), amount);
            IMezoStaking(mezoStaking).createLockFor(amount, lockDuration, to);
        }
    }

    // ================================= ADMIN =================================

    /// @notice Updates the lock duration used for future claims
    function setLockDuration(uint256 _newLockDuration) external onlyHolderOrGovernor {
        lockDuration = _newLockDuration;
        emit LockDurationUpdated(_newLockDuration);
    }

    /// @notice Resets the token allowance granted to the Mezo staking contract
    function setStakingAllowance(uint256 _allowance) external onlyHolderOrGovernor {
        IERC20(token).safeApprove(mezoStaking, 0);
        IERC20(token).safeApprove(mezoStaking, _allowance);
    }
}
