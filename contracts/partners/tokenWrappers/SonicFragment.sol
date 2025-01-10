// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title SonicFragment
/// @author Angle Labs, Inc.
contract SonicFragment is ERC2O {
    using SafeERC20 for IERC20;

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;
    uint256 public exchangeRate;
    address public sToken;
    uint8 public contractSettled;

    constructor(
        address _accessControlManager,
        address recipient,
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        // Zero address check
        IAccessControlManager(_accessControlManager).isGovernor(msg.sender);
        accessControlManager = IAccessControlManager(_accessControlManager);
        _mint(recipient, _totalSupply);
    }

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier isGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotAllowed();
        _;
    }

    /// @notice Activates the contract settlement and enables redemption of fragments into S
    function settleContract(uint256 sTokenAmount) external isGovernor {
        if (contractSettled > 0) revert Errors.NotAllowed();
        IERC20(sToken).safeTransferFrom(msg.sender, address(this), sTokenAmount);
        contractSettled = 1;
        uint256 _totalSupply = totalSupply();
        exchangeRate = (sTokenAmount * 1 ether) / _totalSupply;
    }

    /// @notice Sets the S address
    /// @dev Cannot be set once redemption is activated
    function setSTokenAddress(address sTokenAddress) external isGovernor {
        if (contractSettled == 0) sToken = sTokenAddress;
    }

    /// @notice Redeems fragments against S
    function redeem(uint256 amount, address recipient) external {
        _burn(msg.sender, amount);
        uint256 amountToSend = (amount * exchangeRate) / 1 ether;
        IERC20(sToken).safeTransfer(recipient, amount);
    }

    /// @notice Recovers leftover tokens after sometime
    function recover(uint256 amount, address recipient) external onlyGovernor {
        IERC20(sToken).safeTransfer(recipient, amount);
        exchangeRate = 0;
    }
}
