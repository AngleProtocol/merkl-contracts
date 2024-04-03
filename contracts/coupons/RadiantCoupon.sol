// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../utils/UUPSHelper.sol";

contract RadiantCoupon is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice `Core` contract handling access control
    ICore public core;

    // =================================== EVENTS ==================================

    event Recovered(address indexed token, address indexed to, uint256 amount);

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!core.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    // ================================= FUNCTIONS =================================

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
        // TODO: check allowance issue
        if (to == address(FEE_MANAGER)) {
            IERC20(RADIANT).safeTransferFrom(from, address(FEE_MANAGER), amount);
            _mint(from, amount); // These are then transferred to the fee manager
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (to == address(FEE_MANAGER)) {
            _burn(to, amount); // To avoid having any token aside from on the distributor
        } else if (from == address(DISTRIBUTOR)) {
            _burn(to, amount);
            // HERE CALL THE VESTING CONTRACT TO STAKE ON BEHALF OF THE USER
        }
    }

    /// @notice Recovers any ERC20 token
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(core) {}
}
