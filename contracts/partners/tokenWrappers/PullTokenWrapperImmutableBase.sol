// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { DistributionCreator } from "../../DistributionCreator.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title PullTokenWrapperImmutableBase
/// @notice Abstract base for non-upgradeable pull token wrappers on Merkl
/// @dev Provides shared state, access control, allowance tracking, and common functions.
/// Child contracts must implement `_beforeTokenTransfer` to define how tokens are delivered on claim,
/// and call the ERC20 constructor with the appropriate name and symbol.
abstract contract PullTokenWrapperImmutableBase is ERC20 {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public immutable accessControlManager;
    /// @notice Address of the token involved in the pull mechanism
    address public immutable token;
    /// @notice Address of the Merkl distributor contract
    address public immutable distributor;
    /// @notice Address of the Merkl distribution creator contract
    address public immutable distributionCreator;
    /// @notice Address holding the tokens and granting allowance to this contract
    address public holder;
    /// @notice Address receiving protocol fees on claim
    address public feeRecipient;
    /// @notice Whether an address is allowed to hold wrapper tokens
    mapping(address => uint256) public isAllowed;

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` is the holder or a governor
    modifier onlyHolderOrGovernor() {
        if (msg.sender != holder && !accessControlManager.isGovernor(msg.sender)) revert Errors.NotAllowed();
        _;
    }

    // ================================= CONSTRUCTOR =================================

    constructor(address _token, address _distributionCreator, address _holder) {
        if (_holder == address(0) || _distributionCreator == address(0)) revert Errors.ZeroAddress();
        DistributionCreator dc = DistributionCreator(_distributionCreator);
        address _distributor = dc.distributor();
        accessControlManager = dc.accessControlManager();
        distributor = _distributor;
        feeRecipient = dc.feeRecipient();
        token = _token;
        distributionCreator = _distributionCreator;
        holder = _holder;
        isAllowed[_distributor] = 1;
        isAllowed[_holder] = 1;
        isAllowed[address(0)] = 1;
    }

    // ================================= FUNCTIONS =================================

    /// @notice Hook called after every transfer: burns wrapper tokens for any recipient that is not allowed
    function _afterTokenTransfer(address, address to, uint256 amount) internal override {
        if (isAllowed[to] == 0) _burn(to, amount);
    }

    /// @notice Mints wrapper tokens to a recipient and allows them to hold wrapper tokens
    /// @param recipient Address to receive the minted wrapper tokens
    /// @param amount Amount of wrapper tokens to mint
    function mint(address recipient, uint256 amount) external onlyHolderOrGovernor {
        isAllowed[recipient] = 1;
        _mint(recipient, amount);
    }

    /// @notice Updates the holder address and adjusts allowances accordingly
    /// @param _newHolder New holder address
    function setHolder(address _newHolder) external onlyHolderOrGovernor {
        isAllowed[holder] = 0;
        isAllowed[_newHolder] = 1;
        holder = _newHolder;
    }

    /// @notice Toggles whether an address is allowed to hold wrapper tokens
    /// @param _address Address to toggle allowance for
    function toggleAllowance(address _address) external onlyHolderOrGovernor {
        isAllowed[_address] = 1 - isAllowed[_address];
    }

    /// @notice Recovers ERC20 tokens held by this contract
    /// @param _token Address of the token to recover
    /// @param _to Address to send the recovered tokens to
    /// @param amount Amount to recover
    function recover(address _token, address _to, uint256 amount) external onlyHolderOrGovernor {
        IERC20(_token).safeTransfer(_to, amount);
    }

    /// @notice Syncs the fee recipient from the DistributionCreator contract
    function setFeeRecipient() external {
        feeRecipient = DistributionCreator(distributionCreator).feeRecipient();
    }

    /// @notice Returns the number of decimals of the token
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(token).decimals();
    }
}
