// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { DistributionCreator } from "../../DistributionCreator.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title PullTokenWrapperAllowImmutable
/// @notice Non-upgradeable wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev Tokens are pulled from a holder address via allowance during claims
contract PullTokenWrapperAllowImmutable is ERC20 {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    IAccessControlManager public immutable accessControlManager;
    address public immutable token;
    address public immutable distributor;
    address public immutable distributionCreator;
    address public holder;
    address public feeRecipient;

    // ================================= MODIFIERS =================================

    modifier onlyHolderOrGovernor() {
        if (msg.sender != holder && !accessControlManager.isGovernor(msg.sender)) revert Errors.NotAllowed();
        _;
    }

    // ================================= CONSTRUCTOR =================================

    constructor(
        address _token,
        address _distributionCreator,
        address _holder
    ) ERC20(string(abi.encodePacked(IERC20Metadata(_token).name(), " (wrapped)")), IERC20Metadata(_token).symbol()) {
        if (_holder == address(0) || _distributionCreator == address(0)) revert Errors.ZeroAddress();
        DistributionCreator dc = DistributionCreator(_distributionCreator);
        accessControlManager = dc.accessControlManager();
        distributor = dc.distributor();
        feeRecipient = dc.feeRecipient();
        token = _token;
        distributionCreator = _distributionCreator;
        holder = _holder;
    }

    // ================================= FUNCTIONS =================================

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

    function setFeeRecipient() external {
        feeRecipient = DistributionCreator(distributionCreator).feeRecipient();
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(token).decimals();
    }
}
