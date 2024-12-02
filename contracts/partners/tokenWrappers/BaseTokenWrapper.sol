// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { UUPSHelper } from "../../utils/UUPSHelper.sol";
import { IAccessControlManager } from "../../interfaces/IAccessControlManager.sol";
import { Errors } from "../../utils/Errors.sol";

interface IDistributionCreator {
    function distributor() external view returns (address);
    function feeRecipient() external view returns (address);
}

abstract contract BaseMerklTokenWrapper is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // ================================= CONSTANTS =================================

    IDistributionCreator public constant DISTRIBUTOR_CREATOR =
        IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);

    address public immutable DISTRIBUTOR = DISTRIBUTOR_CREATOR.distributor();
    address public immutable FEE_RECIPIENT = DISTRIBUTOR_CREATOR.feeRecipient();

    // ================================= VARIABLES =================================

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    // =================================== EVENTS ==================================

    event Recovered(address indexed token, address indexed to, uint256 amount);

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    // ================================= FUNCTIONS =================================

    function token() public view virtual returns (address);

    function isTokenWrapper() external pure returns (bool) {
        return true;
    }

    function initialize(IAccessControlManager _accessControlManager) public initializer onlyProxy {
        __ERC20_init(
            string.concat("Merkl Token Wrapper - ", IERC20Metadata(token()).name()),
            string.concat("mtw", IERC20Metadata(token()).symbol())
        );
        __UUPSUpgradeable_init();
        if (address(_accessControlManager) == address(0)) revert Errors.ZeroAddress();
        accessControlManager = _accessControlManager;
    }

    /// @notice Recovers any ERC20 token
    /// @dev Governance only, to trigger only if something went wrong
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(accessControlManager) {}
}
