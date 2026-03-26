// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PublicWrapperBase } from "./PublicWrapperBase.sol";
import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";
import { Errors } from "../../utils/Errors.sol";

interface IWETH {
    function withdraw(uint256 wad) external;
}

/// @title NativeTokenUnwrapperImmutable
/// @notice Non-upgradeable wrapper that takes a wrapped native token (e.g. wETH) and unwraps it to the
/// native token of the chain when users claim via Merkl
contract NativeTokenUnwrapperImmutable is PublicWrapperBase {
    constructor(
        address _wrappedNative,
        address _distributionCreator,
        address _holder,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) PullTokenWrapperImmutableBase(_wrappedNative, _distributionCreator, _holder) {}

    /// @notice Allows the contract to receive native tokens when unwrapping wETH
    receive() external payable {}

    /// @notice On claim: unwraps the wrapped native token and sends native to the recipient
    function _onClaim(address to, uint256 amount) internal override {
        IWETH(token).withdraw(amount);
        (bool success, ) = to.call{ value: amount }("");
        if (!success) revert Errors.WithdrawalFailed();
    }

    /// @notice Recovers native tokens held by this contract
    function recoverETH(address payable _to, uint256 amount) external onlyHolderOrGovernor {
        (bool success, ) = _to.call{ value: amount }("");
        if (!success) revert Errors.WithdrawalFailed();
    }

    /// @notice Returns 18 decimals for native token
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
