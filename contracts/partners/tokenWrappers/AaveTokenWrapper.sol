// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { DistributionCreator } from "../../DistributionCreator.sol";
import { UUPSHelper } from "../../utils/UUPSHelper.sol";
import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { Errors } from "../../utils/Errors.sol";

contract AaveTokenWrapper is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // ================================= VARIABLES =================================

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    // could be put as immutable in non upgradeable contract
    address public token;
    address public distributor;
    address public distributionCreator;

    mapping(address => uint256) public isMasterClaimer;
    mapping(address => address) public delegateReceiver;
    mapping(address => uint256) public permissionlessClaim;

    // =================================== EVENTS ==================================

    event Recovered(address indexed token, address indexed to, uint256 amount);

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    // ================================= FUNCTIONS =================================

    function initialize(
        address underlyingToken,
        address _distributor,
        address _accessControlManager,
        address _distributionCreator
    ) public initializer {
        // TODO could fetch name and symbol based on real token
        __ERC20_init("AaveTokenWrapper", "ATW");
        __UUPSUpgradeable_init();
        if (underlyingToken == address(0) || _distributor == address(0) || _distributionCreator == address(0))
            revert Errors.ZeroAddress();
        IAccessControlManager(_accessControlManager).isGovernor(msg.sender);
        token = underlyingToken;
        distributor = _distributor;
        distributionCreator = _distributionCreator;
        accessControlManager = IAccessControlManager(_accessControlManager);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Needs an approval before hand, this is how mints are done
        if (to == distributor) {
            IERC20(token).safeTransferFrom(from, address(this), amount);
            _mint(from, amount); // These are then transferred to the distributor
        } else {
            if (to == _getFeeRecipient()) {
                IERC20(token).safeTransferFrom(from, to, amount);
                _mint(from, amount);
            }
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(distributor)) {
            if (tx.origin == to || permissionlessClaim[to] == 1 || isMasterClaimer[tx.origin] == 1) {
                _handleClaim(to, amount);
            } else if (allowance(to, tx.origin) > amount) {
                _spendAllowance(to, tx.origin, amount);
                _handleClaim(to, amount);
            } else {
                revert Errors.InvalidClaim();
            }
        } else if (to == _getFeeRecipient()) {
            // To avoid having any token aside from the distributor
            _burn(to, amount);
        }
    }

    function _handleClaim(address to, uint256 amount) internal {
        address delegate = delegateReceiver[to];
        _burn(to, amount);
        if (delegate == address(0) || delegate == to) {
            IERC20(token).safeTransfer(to, amount);
        } else {
            IERC20(token).safeTransfer(delegate, amount);
        }
    }

    function _getFeeRecipient() internal view returns (address feeRecipient) {
        address _distributionCreator = distributionCreator;
        feeRecipient = DistributionCreator(_distributionCreator).feeRecipient();
        feeRecipient = feeRecipient == address(0) ? _distributionCreator : feeRecipient;
    }

    /// @notice Recovers any ERC20 token
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    function toggleMasterClaimer(address claimer) external onlyGovernor {
        uint256 claimStatus = 1 - isMasterClaimer[claimer];
        isMasterClaimer[claimer] = claimStatus;
    }

    function togglePermissionlessClaim() external {
        uint256 permission = 1 - permissionlessClaim[msg.sender];
        permissionlessClaim[msg.sender] = permission;
    }

    function updateDelegateReceiver(address receiver) external {
        delegateReceiver[msg.sender] = receiver;
    }

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(accessControlManager) {}
}
