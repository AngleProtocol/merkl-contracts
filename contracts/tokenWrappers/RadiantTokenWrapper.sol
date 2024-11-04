// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseMerklTokenWrapper } from "./BaseTokenWrapper.sol";

interface IVesting {
    function rdntToken() external view returns (address);
    function vestTokens(address, uint256, bool) external;
}

/// @title Radiant MTW
/// @dev This token can only be held by merkl distributor
/// @dev Transferring to the distributor will require transferring the underlying token to this contract
/// @dev Transferring from the distributor will trigger vesting action
/// @dev Transferring token to the distributor is permissionless so anyone could mint this wrapper - the only
/// impact would be to forfeit these tokens
contract RadiantMerklTokenWrapper is BaseMerklTokenWrapper {
    using SafeERC20 for IERC20;

    // ================================= CONSTANTS =================================

    IVesting public constant VESTING = IVesting(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
    address internal immutable _UNDERLYING = VESTING.rdntToken();

    // ================================= FUNCTIONS =================================

    function token() public view override returns (address) {
        return _UNDERLYING;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Needs an RDNT approval beforehand, this is how mints of coupons are done
        if (to == DISTRIBUTOR) {
            IERC20(_UNDERLYING).safeTransferFrom(from, address(this), amount);
            _mint(from, amount); // These are then transferred to the distributor
        }

        // Will be burn right after, to avoid having any token aside from on the distributor
        if (to == FEE_RECIPIENT) {
            IERC20(_UNDERLYING).safeTransferFrom(from, FEE_RECIPIENT, amount);
            _mint(from, amount); // These are then transferred to the fee manager
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (to == FEE_RECIPIENT) {
            _burn(to, amount); // To avoid having any token aside from on the distributor
        }

        if (from == DISTRIBUTOR) {
            _burn(to, amount);

            // Vesting logic
            IERC20(_UNDERLYING).transfer(address(VESTING), amount);
            VESTING.vestTokens(to, amount, true);
        }
    }

    function name() public view override returns (string memory) {
        return string.concat("Merkl Token Wrapper - ", IERC20Metadata(token()).name());
    }

    function symbol() public view override returns (string memory) {
        return string.concat("mtw", IERC20Metadata(token()).symbol());
    }
}
