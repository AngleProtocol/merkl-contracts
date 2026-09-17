// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PullTokenWrapperImmutableBase } from "./PullTokenWrapperImmutableBase.sol";
import { IAaveToken } from "../../interfaces/external/IAaveToken.sol";
import { IAavePool } from "../../interfaces/external/IAavePool.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title PullTokenWrapperImmutableAaveDebt
/// @notice Non-upgradeable wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev In this version of the PullTokenWrapper, 1 wrapper token is worth 1 unit of the underlying asset
/// (e.g. USDC) and rewards are delivered as a debt repayment rather than as a transfer: during a claim, funds
/// are pulled from the holder and repaid on Aave on behalf of the claimer
/// @dev The holder may hold either the underlying asset (e.g. USDC) or the aToken of the same reserve
/// (e.g. aUSDC): in the latter case the aTokens pulled are first withdrawn from Aave before the repayment
/// @dev The amount actually pulled is capped by the claimer's current debt: if the claimer has no debt left,
/// nothing is pulled from the holder and the wrapper tokens are simply burnt; if the claim exceeds the debt,
/// only the debt is repaid and the unused budget stays with the holder
/// @dev Managers of such wrapper contracts must ensure that the holder address has enough allowance to the wrapper
/// contract for the token pulled during claims
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
    /// @notice Address of the asset whose debt is repaid, and in which the wrapper is denominated
    /// @dev This may differ from `token`: `token` is what is pulled from the holder (the underlying itself or
    /// the aToken of the same reserve), `underlying` is what is repaid on Aave
    address public immutable underlying;

    // ================================= CONSTRUCTOR =================================

    /// @param _debtToken Address of the Aave variable debt token of the asset being distributed: the underlying
    /// asset and the pool are both derived from it
    /// @param _holderToken Address of the token held by the holder and pulled during claims: either the underlying
    /// asset itself or the aToken of the same reserve
    constructor(
        address _debtToken,
        address _holderToken,
        address _distributionCreator,
        address _holder
    )
        ERC20(
            string(abi.encodePacked(IERC20Metadata(IAaveToken(_debtToken).UNDERLYING_ASSET_ADDRESS()).name(), " (wrapped)")),
            IERC20Metadata(IAaveToken(_debtToken).UNDERLYING_ASSET_ADDRESS()).symbol()
        )
        PullTokenWrapperImmutableBase(_holderToken, _distributionCreator, _holder)
    {
        address _underlying = IAaveToken(_debtToken).UNDERLYING_ASSET_ADDRESS();
        address _pool = IAaveToken(_debtToken).POOL();
        // When the holder does not hold the underlying, it must hold the aToken of the very same reserve,
        // otherwise the amount withdrawn during a claim would not match the debt being repaid
        if (_holderToken != _underlying) {
            if (IAaveToken(_holderToken).UNDERLYING_ASSET_ADDRESS() != _underlying || IAaveToken(_holderToken).POOL() != _pool)
                revert Errors.InvalidParam();
        }
        pool = _pool;
        debtToken = _debtToken;
        underlying = _underlying;
        IERC20(_underlying).forceApprove(_pool, type(uint256).max);
    }

    // ================================= FUNCTIONS =================================

    /// @notice Resets the allowance given to the Aave pool on the underlying asset
    /// @dev Only useful if the allowance set at deployment ends up being consumed
    function approvePool() external {
        IERC20(underlying).forceApprove(pool, type(uint256).max);
    }

    /// @notice Hook called before every transfer: pulls funds from the holder and repays the Aave debt of the
    /// recipient when the transfer originates from the distributor (claim) or is directed to the fee recipient
    /// @dev The amount repaid is the minimum between the claimed amount and the current debt of the recipient:
    /// nothing is pulled from the holder for the part of the claim that exceeds the debt
    /// @dev When the holder holds the aToken rather than the underlying, the aTokens pulled are withdrawn from
    /// Aave first: 1 aToken always redeems for 1 underlying, so the amount repaid is unchanged
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == distributor || to == feeRecipient) {
            uint256 toTransfer = _underlyingToTransfer(to, amount);
            if (toTransfer != 0) {
                uint256 debt = IERC20(debtToken).balanceOf(to);
                if (debt < toTransfer) toTransfer = debt;
                if (toTransfer != 0) {
                    address _underlying = underlying;
                    IERC20(token).safeTransferFrom(holder, address(this), toTransfer);
                    if (token != _underlying) IAavePool(pool).withdraw(_underlying, toTransfer, address(this));
                    IAavePool(pool).repay(_underlying, toTransfer, INTEREST_RATE_MODE, to);
                }
            }
        }
    }
}
