// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAccessControlManager } from "./BaseTokenWrapper.sol";

import { UUPSHelper } from "../../utils/UUPSHelper.sol";
import { Errors } from "../../utils/Errors.sol";

interface IDistributionCreator {
    function distributor() external view returns (address);
    function feeRecipient() external view returns (address);
}

interface IEtherealExchange {
    function depositOnBehalf(uint256 _amount, address receiver) external;
}

/// @title EtherealWrapper
/// @dev This token can only be held by Merkl distributor
/// @dev Transferring to the distributor will require transferring the underlying token to this contract
contract EtherealWrapper is UUPSHelper, ERC20Upgradeable {
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
    address public etherealExchange;

    /// @notice Underlying token used
    address public underlying;

    event Recovered(address indexed token, address indexed to, uint256 amount);
    event MerklAddressesUpdated(address indexed _distributionCreator, address indexed _distributor);
    event CliffDurationUpdated(uint32 _newCliffDuration);
    event FeeRecipientUpdated(address indexed _feeRecipient);

    // ================================= FUNCTIONS =================================

    function initialize(
        address _underlying,
        IAccessControlManager _accessControlManager,
        address _distributionCreator,
        address _etherealExchange
    ) public initializer {
        __ERC20_init(
            string.concat("Merkl Token Wrapper - ", IERC20Metadata(_underlying).name()),
            string.concat("mtw", IERC20Metadata(_underlying).symbol())
        );
        __UUPSUpgradeable_init();
        if (address(_accessControlManager) == address(0) || _etherealExchange == address(0))
            revert Errors.ZeroAddress();
        underlying = _underlying;
        accessControlManager = _accessControlManager;
        distributionCreator = _distributionCreator;
        etherealExchange = _etherealExchange;
        distributor = IDistributionCreator(_distributionCreator).distributor();
        feeRecipient = IDistributionCreator(_distributionCreator).feeRecipient();
        IERC20(underlying).safeApprove(_etherealExchange, type(uint256).max);
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
            _burn(to, amount);
        }

        if (from == address(distributor)) {
            _burn(to, amount);
            IEtherealExchange(etherealExchange).depositOnBehalf(amount, to);
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
        address _distributor = IDistributionCreator(_distributionCreator).distributor();
        distributor = _distributor;
        distributionCreator = _distributionCreator;
        emit MerklAddressesUpdated(_distributionCreator, _distributor);
        _setFeeRecipient();
    }

    function setFeeRecipient() external {
        _setFeeRecipient();
    }

    function _setFeeRecipient() internal {
        address _feeRecipient = IDistributionCreator(distributionCreator).feeRecipient();
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }
}
