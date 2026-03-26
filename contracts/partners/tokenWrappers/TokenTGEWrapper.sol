// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PublicWrapperBase } from "./PublicWrapperBase.sol";
import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title TokenTGEWrapper
/// @notice Non-upgradeable wrapper that locks underlying tokens until a TGE unlock timestamp
contract TokenTGEWrapper is PublicWrapperBase {
    using SafeERC20 for IERC20;

    /// @notice Timestamp before which tokens cannot be claimed
    uint256 public unlockTimestamp;

    event UnlockTimestampUpdated(uint256 newUnlockTimestamp);

    constructor(
        address _token,
        address _distributionCreator,
        address _holder,
        uint256 _unlockTimestamp
    )
        ERC20(
            string(abi.encodePacked(IERC20Metadata(_token).name(), " (wrapped)")),
            IERC20Metadata(_token).symbol()
        )
        PullTokenWrapperImmutableBase(_token, _distributionCreator, _holder)
    {
        unlockTimestamp = _unlockTimestamp;
    }

    /// @notice On claim: checks unlock timestamp, then sends underlying to the claimer
    function _onClaim(address to, uint256 amount) internal override {
        if (block.timestamp < unlockTimestamp) revert Errors.NotAllowed();
        IERC20(token).safeTransfer(to, amount);
    }

    // ================================= ADMIN =================================

    /// @notice Updates the unlock timestamp
    function setUnlockTimestamp(uint256 _newUnlockTimestamp) external onlyHolderOrGovernor {
        unlockTimestamp = _newUnlockTimestamp;
        emit UnlockTimestampUpdated(_newUnlockTimestamp);
    }
}
