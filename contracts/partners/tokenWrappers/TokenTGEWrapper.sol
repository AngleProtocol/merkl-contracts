// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";

import { UUPSHelper } from "../../utils/UUPSHelper.sol";
import { Errors } from "../../utils/Errors.sol";
import { DistributionCreator } from "../../DistributionCreator.sol";

/// @title TokenTGEWrapper
/// @dev This token can only be held by Merkl distributor
/// @dev Transferring to the distributor will require transferring the underlying token to this contract
/// @dev Transferring from the distributor will trigger a vesting action
/// @dev Transferring token to the distributor is permissionless so anyone could mint this wrapper - the only
/// impact would be to forfeit these tokens
contract TokenTGEWrapper is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    /// @notice `accessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;
    /// @notice Merkl main functions
    address public distributor;
    address public feeRecipient;
    address public distributionCreator;

    /// @notice Underlying token used
    address public underlying;
    /// @notice Timestamp before which tokens cannot be claimed
    uint256 public unlockTimestamp;

    event Recovered(address indexed token, address indexed to, uint256 amount);
    event MerklAddressesUpdated(address indexed _distributionCreator, address indexed _distributor);
    event UnlockTimestampUpdated(uint256 _newUnlockTimestamp);
    event FeeRecipientUpdated(address indexed _feeRecipient);

    // ================================= FUNCTIONS =================================

    function initialize(address _underlying, uint256 _unlockTimestamp, address _distributionCreator) public initializer {
        __ERC20_init(string.concat(IERC20Metadata(_underlying).name(), " (wrapped)"), IERC20Metadata(_underlying).symbol());
        __UUPSUpgradeable_init();
        underlying = _underlying;
        accessControlManager = DistributionCreator(_distributionCreator).accessControlManager();
        unlockTimestamp = _unlockTimestamp;
        distributionCreator = _distributionCreator;
        distributor = DistributionCreator(_distributionCreator).distributor();
        feeRecipient = DistributionCreator(_distributionCreator).feeRecipient();
    }

    function isTokenWrapper() external pure returns (bool) {
        return true;
    }

    function token() public view returns (address) {
        return underlying;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Needs an underlying approval beforehand, this is how mints of wrappers are done
        if (to == distributor) {
            IERC20(underlying).safeTransferFrom(from, address(this), amount);
            _mint(from, amount); // These are then transferred to the distributor
        }

        // Will be burnt right after, to avoid having any token aside from on the distributor
        if (to == feeRecipient) {
            IERC20(underlying).safeTransferFrom(from, feeRecipient, amount);
            _mint(from, amount); // These are then transferred to the fee manager
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (to == feeRecipient) {
            _burn(to, amount); // To avoid having any token aside from on the distributor
        }

        if (from == distributor) {
            if (block.timestamp < unlockTimestamp) revert Errors.NotAllowed();
            _burn(to, amount);
            IERC20(token()).safeTransfer(to, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    ADMIN FUNCTIONS                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGuardian() {
        if (!accessControlManager.isGovernorOrGuardian(msg.sender)) revert Errors.NotGovernorOrGuardian();
        _;
    }

    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(accessControlManager) {}

    /// @notice Recovers any ERC20 token
    /// @dev Governance only, to trigger only if something went wrong
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    function setDistributor(address _distributionCreator) external onlyGovernor {
        address _distributor = DistributionCreator(_distributionCreator).distributor();
        distributor = _distributor;
        distributionCreator = _distributionCreator;
        emit MerklAddressesUpdated(_distributionCreator, _distributor);
        _setFeeRecipient();
    }

    function setUnlockTimestamp(uint256 _newUnlockTimestamp) external onlyGuardian {
        unlockTimestamp = _newUnlockTimestamp;
        emit UnlockTimestampUpdated(_newUnlockTimestamp);
    }

    function setFeeRecipient() external {
        _setFeeRecipient();
    }

    function _setFeeRecipient() internal {
        address _feeRecipient = DistributionCreator(distributionCreator).feeRecipient();
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }
}
