// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { DistributionCreator } from "../../DistributionCreator.sol";
import { UUPSHelper } from "../../utils/UUPSHelper.sol";
import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title PullTokenWrapperTransfer
/// @notice Wrapper for a reward token on Merkl so campaigns do not have to be prefunded
/// @dev In this version of the PullTokenWrapper, tokens are pulled directly from the wrapper contract during claims
/// @dev Managers of such wrapper contracts must ensure to transfer enough tokens to the wrapper contract before claims happen
contract PullTokenWrapperTransfer is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;
    /// @notice Underlying token used and transferred to users claiming on Merkl
    address public token;
    /// @notice Minter address that can mint tokens and set allowed addresses
    address public minter;
    /// @notice Merkl fee recipient
    address public feeRecipient;
    /// @notice Merkl main address
    address public distributor;
    address public distributionCreator;
    /// @notice Whether an address is allowed to hold some tokens and thus to create campaigns on Merkl
    mapping(address => uint256) public isAllowed;

    uint256[43] private __gap;

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyMinterOrGovernor() {
        if (msg.sender != minter && !accessControlManager.isGovernor(msg.sender)) revert Errors.NotAllowed();
        _;
    }

    // ================================= FUNCTIONS =================================

    function initialize(
        address _token,
        address _distributionCreator,
        address _minter,
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC20_init(string.concat(_name), string.concat(_symbol));
        __UUPSUpgradeable_init();
        if (_minter == address(0)) revert Errors.ZeroAddress();
        IERC20(_token).balanceOf(_minter);
        address _distributor = DistributionCreator(_distributionCreator).distributor();
        distributor = _distributor;
        accessControlManager = DistributionCreator(_distributionCreator).accessControlManager();
        token = _token;
        distributionCreator = _distributionCreator;
        minter = _minter;
        isAllowed[_distributor] = 1;
        isAllowed[_minter] = 1; // The minter is allowed to hold tokens
        isAllowed[address(0)] = 1; // The zero address is allowed to hold tokens (for burning)
        _setFeeRecipient();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // During claim transactions, tokens are transferred to the `to` address
        if (from == distributor || to == feeRecipient) IERC20(token).safeTransfer(to, amount);
    }

    function _afterTokenTransfer(address, address to, uint256 amount) internal override {
        // No leftover tokens can be kept except on allowed addresses
        if (isAllowed[to] == 0) _burn(to, amount);
    }

    function setMinter(address _newMinter) external onlyMinterOrGovernor {
        address _oldMinter = minter;
        isAllowed[_oldMinter] = 0; // Remove the old minter from the allowed list
        isAllowed[_newMinter] = 1; // Add the new minter to the allowed list
        minter = _newMinter;
    }

    function mint(address recipient, uint256 amount) external onlyMinterOrGovernor {
        isAllowed[recipient] = 1; // Allow the recipient to hold tokens
        _mint(recipient, amount);
    }

    function toggleAllowance(address _address) external onlyMinterOrGovernor {
        uint256 currentStatus = isAllowed[_address];
        isAllowed[_address] = 1 - currentStatus;
    }

    function recover(address _token, address _to, uint256 amount) external onlyMinterOrGovernor {
        IERC20(_token).safeTransfer(_to, amount);
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
