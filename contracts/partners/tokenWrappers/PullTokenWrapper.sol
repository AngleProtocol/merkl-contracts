// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { DistributionCreator } from "../../DistributionCreator.sol";
import { UUPSHelper } from "../../utils/UUPSHelper.sol";
import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title PullTokenWrapper
/// @notice Wrapper for a reward token on Merkl so campaigns do not have to be prefunded
contract PullTokenWrapper is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    // Could be put as immutable in a non upgradeable contract
    address public token;
    address public holder;
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
        address underlyingToken,
        address _accessControlManager,
        address _distributionCreator,
        address _holder,
        string memory name,
        string memory symbol
    ) public initializer {
        __ERC20_init(string.concat(name), string.concat(symbol));
        __UUPSUpgradeable_init();
        if (underlyingToken == address(0) || holder == address(0)) revert Errors.ZeroAddress();
        IAccessControlManager(_accessControlManager).isGovernor(msg.sender);
        distributor = DistributionCreator(_distributionCreator).distributor();
        token = underlyingToken;
        distributionCreator = _distributionCreator;
        holder = _holder;
        accessControlManager = IAccessControlManager(_accessControlManager);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // During claim transactions, tokens are pulled and transferred to the `to` address
        if (from == distributor || to == _getFeeRecipient()) IERC20(token).safeTransferFrom(holder, to, amount);
    }

    function _afterTokenTransfer(address, address to, uint256 amount) internal override {
        // No leftover tokens can be kept except on the holder address
        if (to != address(distributor) && to != holder) _burn(to, amount);
    }

    function _getFeeRecipient() internal view returns (address feeRecipient) {
        address _distributionCreator = distributionCreator;
        feeRecipient = DistributionCreator(_distributionCreator).feeRecipient();
        feeRecipient = feeRecipient == address(0) ? _distributionCreator : feeRecipient;
    }

    function setHolder(address _newHolder) external onlyHolderOrGovernor {
        holder = _newHolder;
    }

    function mint(uint256 amount) external onlyHolderOrGovernor {
        _mint(holder, amount);
    }

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(accessControlManager) {}
}
