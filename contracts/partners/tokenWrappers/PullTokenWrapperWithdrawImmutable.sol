// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";

interface IAaveToken {
    function POOL() external view returns (address);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

interface IAavePool {
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/// @title PullTokenWrapperWithdrawImmutable
/// @notice Non-upgradeable wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev In this version of the PullTokenWrapper, aTokens are pulled from a holder address and withdrawn from
/// Aave during claims, so the recipient receives the underlying asset
/// @dev Managers of such wrapper contracts must ensure that the holder address has enough allowance to the wrapper
/// contract for the aToken pulled during claims
/// @dev This is the non-upgradeable version of `PullTokenWrapperWithdraw`
//solhint-disable
contract PullTokenWrapperWithdrawImmutable is PullTokenWrapperImmutableBase {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice Address of the Aave lending pool used to withdraw the underlying asset
    address public immutable pool;
    /// @notice Address of the underlying asset behind the aToken
    address public immutable underlying;

    // ================================= CONSTRUCTOR =================================

    constructor(
        address _token,
        address _distributionCreator,
        address _holder
    )
        ERC20(
            string(abi.encodePacked(IERC20Metadata(IAaveToken(_token).UNDERLYING_ASSET_ADDRESS()).name(), " (wrapped)")),
            IERC20Metadata(IAaveToken(_token).UNDERLYING_ASSET_ADDRESS()).symbol()
        )
        PullTokenWrapperImmutableBase(_token, _distributionCreator, _holder)
    {
        pool = IAaveToken(_token).POOL();
        underlying = IAaveToken(_token).UNDERLYING_ASSET_ADDRESS();
    }

    // ================================= FUNCTIONS =================================

    /// @notice Hook called before every transfer: pulls aTokens from the holder and withdraws the underlying
    /// asset from Aave to the recipient when the transfer originates from the distributor (claim) or is
    /// directed to the fee recipient
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == distributor || to == feeRecipient) {
            IERC20(token).safeTransferFrom(holder, address(this), amount);
            IAavePool(pool).withdraw(underlying, amount, to);
        }
    }
}
