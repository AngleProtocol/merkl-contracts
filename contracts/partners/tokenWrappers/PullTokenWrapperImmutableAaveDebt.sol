// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";
import { IAaveToken } from "../../interfaces/external/IAaveToken.sol";
import { IAavePool } from "../../interfaces/external/IAavePool.sol";

/// @title PullTokenWrapperImmutableAaveDebt
/// @notice Non-upgradeable wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev In this version of the PullTokenWrapper, 1 wrapper token is worth 1 underlying token (e.g. USDC) and
/// rewards are delivered as a debt repayment rather than as a transfer: during a claim, the underlying is pulled
/// from the holder and repaid on Aave on behalf of the claimer
/// @dev The amount actually pulled is capped by the claimer's current debt: if the claimer has no debt left,
/// nothing is pulled from the holder and the wrapper tokens are simply burnt; if the claim exceeds the debt,
/// only the debt is repaid and the unused budget stays with the holder
/// @dev Managers of such wrapper contracts must ensure that the holder address has enough allowance to the wrapper
/// contract for the underlying pulled during claims
//solhint-disable
contract PullTokenWrapperImmutableAaveDebt is PullTokenWrapperImmutableBase {
    using SafeERC20 for IERC20;

    // ================================= CONSTANTS =================================

    /// @notice Interest rate mode of the debt repaid on Aave (2 = variable)
    uint256 public constant INTEREST_RATE_MODE = 2;

    // ================================= VARIABLES =================================

    /// @notice Address of the Aave lending pool on which debt is repaid
    address public immutable pool;
    /// @notice Address of the Aave variable debt token tracking the debt of the claimers
    address public immutable debtToken;

    // ================================= CONSTRUCTOR =================================

    /// @param _debtToken Address of the Aave variable debt token of the asset being distributed: the underlying
    /// asset and the pool are both derived from it
    constructor(
        address _debtToken,
        address _distributionCreator,
        address _holder
    )
        ERC20(
            string(abi.encodePacked(IERC20Metadata(IAaveToken(_debtToken).UNDERLYING_ASSET_ADDRESS()).name(), " (wrapped)")),
            IERC20Metadata(IAaveToken(_debtToken).UNDERLYING_ASSET_ADDRESS()).symbol()
        )
        PullTokenWrapperImmutableBase(IAaveToken(_debtToken).UNDERLYING_ASSET_ADDRESS(), _distributionCreator, _holder)
    {
        address _pool = IAaveToken(_debtToken).POOL();
        pool = _pool;
        debtToken = _debtToken;
        IERC20(IAaveToken(_debtToken).UNDERLYING_ASSET_ADDRESS()).forceApprove(_pool, type(uint256).max);
    }

    // ================================= FUNCTIONS =================================

    /// @notice Resets the allowance given to the Aave pool on the underlying asset
    /// @dev Only useful if the allowance set at deployment ends up being consumed
    function approvePool() external {
        IERC20(token).forceApprove(pool, type(uint256).max);
    }

    /// @notice Hook called before every transfer: pulls the underlying from the holder and repays the Aave debt
    /// of the recipient when the transfer originates from the distributor (claim) or is directed to the fee
    /// recipient
    /// @dev The amount repaid is the minimum between the claimed amount and the current debt of the recipient:
    /// no underlying is pulled from the holder for the part of the claim that exceeds the debt
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == distributor || to == feeRecipient) {
            uint256 toTransfer = _underlyingToTransfer(to, amount);
            if (toTransfer != 0) {
                uint256 debt = IERC20(debtToken).balanceOf(to);
                if (debt < toTransfer) toTransfer = debt;
                if (toTransfer != 0) {
                    IERC20(token).safeTransferFrom(holder, address(this), toTransfer);
                    IAavePool(pool).repay(token, toTransfer, INTEREST_RATE_MODE, to);
                }
            }
        }
    }
}
