// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../utils/UUPSHelper.sol";

interface IDistributionCreator {
    function distributor() external view returns (address);
    function feeRecipient() external view returns (address);
}

interface IVesting {
    function rdntToken() external view returns (address);
    function vestTokens(address, uint256, bool) external returns (address);
}

/// @title Radiant Coupon
/// @dev This token can only be held by merkl distributor
/// @dev Transferring to the distributor will require transferring the underlying token to this contract
/// @dev Transferring from the distributor will trigger vesting action
/// @dev Transferring token to the distributor is permissionless so anyone could mint coupons - the only
/// impact would be to forfeit these tokens
contract RadiantCoupon is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // ================================= CONSTANTS =================================

    IVesting public constant VESTING = IVesting(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
    IDistributionCreator public constant DISTRIBUTOR_CREATOR =
        IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);

    address public immutable DISTRIBUTOR = DISTRIBUTOR_CREATOR.distributor();
    address public immutable FEE_RECIPIENT = DISTRIBUTOR_CREATOR.feeRecipient();
    address public immutable RADIANT = VESTING.rdntToken();

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

    function initialize(ICore _core) public initializer onlyProxy {
        __ERC20_init("RadiantCoupon", "cpRDNT");
        __UUPSUpgradeable_init();
        if (address(_core) == address(0)) revert ZeroAddress();
        core = _core;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Needs an RDNT approval beforehand, this is how mints of coupons are done
        if (to == DISTRIBUTOR) {
            IERC20(RADIANT).safeTransferFrom(from, address(this), amount);
            _mint(from, amount); // These are then transfered to the distributor
        }

        // Will be burn right after, to avoid having any token aside from on the distributor
        if (to == FEE_RECIPIENT) {
            IERC20(RADIANT).safeTransferFrom(from, FEE_RECIPIENT, amount);
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
            IERC20(RADIANT).transfer(address(VESTING), amount);
            VESTING.vestTokens(to, amount, true);
        }
    }

    /// @notice Recovers any ERC20 token
    /// @dev Governance only, to trigger only if something went wrong
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(core) {}
}
