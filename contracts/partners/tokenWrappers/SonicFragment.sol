// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title SonicFragment
/// @notice Contract for Sonic fragments which can be converted upon activation into S tokens
/// @author Merkl SAS
contract SonicFragment is ERC20 {
    using SafeERC20 for IERC20;

    /// @notice Contract handling access control
    IAccessControlManager public immutable accessControlManager;
    /// @notice Address for the S token
    address public immutable sToken;

    /// @notice Amount of S tokens sent on the contract at the activation of redemption
    /// @dev Used to compute the exchange rate between fragments and S tokens
    uint128 public sTokenAmount;
    /// @notice Total supply of the contract
    /// @dev Needs to be stored to compute the exchange rate between fragments and sTokens
    uint120 public supply;
    /// @notice Whether redemption for S tokens has been activated or not
    uint8 public contractSettled;

    constructor(
        address _accessControlManager,
        address recipient,
        address _sToken,
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        // Zero address check
        if (_sToken == address(0)) revert Errors.ZeroAddress();
        IAccessControlManager(_accessControlManager).isGovernor(msg.sender);
        sToken = _sToken;
        accessControlManager = IAccessControlManager(_accessControlManager);
        supply = uint120(_totalSupply);
        _mint(recipient, _totalSupply);
    }

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotAllowed();
        _;
    }

    /// @notice Activates the contract settlement and enables redemption of fragments into S
    /// @dev Can only be called once
    function settleContract(uint256 _sTokenAmount) external onlyGovernor {
        if (contractSettled > 0) revert Errors.NotAllowed();
        contractSettled = 1;
        IERC20(sToken).safeTransferFrom(msg.sender, address(this), sTokenAmount);
        sTokenAmount = uint128(_sTokenAmount);
    }

    /// @notice Recovers leftover tokens after sometime
    function recover(uint256 amount, address recipient) external onlyGovernor {
        IERC20(sToken).safeTransfer(recipient, amount);
        sTokenAmount = 0;
    }

    /// @notice Redeems fragments against S based on a predefined exchange rate
    function redeem(uint256 amount, address recipient) external returns (uint256 amountToSend) {
        uint128 _sTokenAmount = sTokenAmount;
        if (_sTokenAmount == 0) revert Errors.NotAllowed();
        _burn(msg.sender, amount);
        amountToSend = (amount * _sTokenAmount) / supply;
        IERC20(sToken).safeTransfer(recipient, amountToSend);
    }
}
