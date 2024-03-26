// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../utils/UUPSHelper.sol";

contract RadiantCoupon is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    /// @notice `Core` contract handling access control
    ICore public core;

    function initialize() public initializer {
        __ERC20_init("RadiantCoupon", "cpRDNT");
        __UUPSUpgradeable_init();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Needs an approval before hand, this is how mints are done
        if (to == address(DISTRIBUTOR)) {
            IERC20(RADIANT).safeTransferFrom(from, address(this), amount);
            _mint(from, amount); // These are then transfered to the distributor
        }
        if (to == address(FEE_MANAGER)) {
            IERC20(RADIANT).safeTransferFrom(from, address(FEE_MANAGER), amount);
            _mint(from, amount); // These are then transferred to the fee manager
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (to == address(FEE_MANAGER)) {
            _burn(to, amount); // To avoid having any token aside from on the distributor
        }
        if (from == address(DISTRIBUTOR)) {
            _burn(to, amount);
            // HERE CALL THE VESTING CONTRACT TO STAKE ON BEHALF OF THE USER
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(core) {}
}
