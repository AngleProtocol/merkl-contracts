// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { DistributionCreator } from "../../DistributionCreator.sol";
import { UUPSHelper } from "../../utils/UUPSHelper.sol";
import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title PullTokenWrapperAllow
/// @notice Wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev In this version of the PullTokenWrapper, tokens are pulled from a holder address during claims
/// @dev Managers of such wrapper contracts must ensure that the holder address has enough allowance to the wrapper contract
/// for the token pulled during claims
contract PullTokenWrapperAllow is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    // Could be put as immutable in a non upgradeable contract
    address public token;
    address public holder;
    address public feeRecipient;
    address public distributor;
    address public distributionCreator;

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyHolderOrGovernor() {
        if (msg.sender != holder && !accessControlManager.isGovernor(msg.sender)) revert Errors.NotAllowed();
        _;
    }

    // ================================= FUNCTIONS =================================

    function initialize(
        address _token,
        address _distributionCreator,
        address _holder,
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC20_init(string.concat(_name), string.concat(_symbol));
        __UUPSUpgradeable_init();
        if (_holder == address(0)) revert Errors.ZeroAddress();
        IERC20(_token).balanceOf(_holder);
        distributor = DistributionCreator(_distributionCreator).distributor();
        accessControlManager = DistributionCreator(_distributionCreator).accessControlManager();
        token = _token;
        distributionCreator = _distributionCreator;
        holder = _holder;
        _setFeeRecipient();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // During claim transactions, tokens are pulled and transferred to the `to` address
        if (from == distributor || to == feeRecipient) IERC20(token).safeTransferFrom(holder, to, amount);
    }

    function _afterTokenTransfer(address, address to, uint256 amount) internal override {
        // No leftover tokens can be kept except on the holder address
        if (to != address(distributor) && to != holder && to != address(0)) _burn(to, amount);
    }

    function setHolder(address _newHolder) external onlyHolderOrGovernor {
        holder = _newHolder;
    }

    function mint(uint256 amount) external onlyHolderOrGovernor {
        _mint(holder, amount);
    }

    function setFeeRecipient() external {
        _setFeeRecipient();
    }

    function _setFeeRecipient() internal {
        address _feeRecipient = DistributionCreator(distributionCreator).feeRecipient();
        feeRecipient = _feeRecipient;
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(accessControlManager) {}
}
