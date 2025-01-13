// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAccessControlManager } from "./BaseTokenWrapper.sol";

import "../../utils/UUPSHelper.sol";
import "../../utils/Errors.sol";

struct VestingID {
    uint128 amount;
    uint128 unlockTimestamp;
}

struct VestingData {
    VestingID[] allVestings;
    uint256 nextClaimIndex;
}

interface IDistributionCreator {
    function distributor() external view returns (address);
    function feeRecipient() external view returns (address);
}

/// @title PufferPointTokenWrapper
/// @dev This token can only be held by Merkl distributor
/// @dev Transferring to the distributor will require transferring the underlying token to this contract
/// @dev Transferring from the distributor will trigger a vesting action
/// @dev Transferring token to the distributor is permissionless so anyone could mint this wrapper - the only
/// impact would be to forfeit these tokens
contract PufferPointTokenWrapper is UUPSHelper, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    /// @notice `Core` contract handling access control
    IAccessControlManager public core;
    /// @notice Merkl main functions
    address public distributor;
    address public feeRecipient;
    address public distributionCreator;

    /// @notice Underlying token used
    address public underlying;
    /// @notice Duration of the cliff before which tokens can be claimed
    uint32 public cliffDuration;
    /// @notice Maps a user address to its vesting data
    mapping(address => VestingData) public vestingData;

    event Recovered(address indexed token, address indexed to, uint256 amount);
    event MerklAddressesUpdated(address indexed _distributionCreator, address indexed _distributor);
    event CliffDurationUpdated(uint32 _newCliffDuration);
    event FeeRecipientUpdated(address indexed _feeRecipient);

    // ================================= FUNCTIONS =================================

    function initialize(
        address _underlying,
        uint32 _cliffDuration,
        IAccessControlManager _core,
        address _distributionCreator
    ) public initializer {
        __ERC20_init(
            string.concat("Merkl Token Wrapper - ", IERC20Metadata(_underlying).name()),
            string.concat("mtw", IERC20Metadata(_underlying).symbol())
        );
        __UUPSUpgradeable_init();
        if (address(_core) == address(0)) revert ZeroAddress();
        underlying = _underlying;
        core = _core;
        cliffDuration = _cliffDuration;
        distributionCreator = _distributionCreator;
        distributor = IDistributionCreator(_distributionCreator).distributor();
        feeRecipient = IDistributionCreator(_distributionCreator).feeRecipient();
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
            _burn(to, amount);

            uint128 endTimestamp = uint128(block.timestamp + cliffDuration);
            if (endTimestamp > block.timestamp) {
                // Creates a vesting for the `to` address
                VestingData storage userVestingData = vestingData[to];
                VestingID[] storage userAllVestings = userVestingData.allVestings;
                userAllVestings.push(VestingID(uint128(amount), uint128(block.timestamp + cliffDuration)));
            } else {
                IERC20(token()).safeTransfer(to, amount);
            }
        }
    }

    function claim(address user) external returns (uint256) {
        return claim(user, type(uint256).max);
    }

    function claim(address user, uint256 maxClaimIndex) public returns (uint256) {
        (uint256 claimed, uint256 nextClaimIndex) = _claimable(user, maxClaimIndex);
        if (claimed > 0) {
            vestingData[user].nextClaimIndex = nextClaimIndex;
            IERC20(token()).safeTransfer(user, claimed);
        }
        return claimed;
    }

    function claimable(address user) external view returns (uint256 amountClaimable) {
        return claimable(user, type(uint256).max);
    }

    function claimable(address user, uint256 maxClaimIndex) public view returns (uint256 amountClaimable) {
        (amountClaimable, ) = _claimable(user, maxClaimIndex);
    }

    function getUserVestings(
        address user
    ) external view returns (VestingID[] memory allVestings, uint256 nextClaimIndex) {
        VestingData storage userVestingData = vestingData[user];
        allVestings = userVestingData.allVestings;
        nextClaimIndex = userVestingData.nextClaimIndex;
    }

    function _claimable(
        address user,
        uint256 maxClaimIndex
    ) internal view returns (uint256 amountClaimable, uint256 nextClaimIndex) {
        VestingData storage userVestingData = vestingData[user];
        VestingID[] storage userAllVestings = userVestingData.allVestings;
        uint256 i = userVestingData.nextClaimIndex;
        uint256 length = userAllVestings.length;
        while (i < length && i <= maxClaimIndex) {
            VestingID storage userCurrentVesting = userAllVestings[i];
            if (block.timestamp > userCurrentVesting.unlockTimestamp) {
                amountClaimable += userCurrentVesting.amount;
                nextClaimIndex = ++i;
            } else break;
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    ADMIN FUNCTIONS                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!core.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGuardian() {
        if (!core.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(core) {}

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

    function setCliffDuration(uint32 _newCliffDuration) external onlyGuardian {
        if (_newCliffDuration < cliffDuration && _newCliffDuration != 0) revert InvalidParam();
        cliffDuration = _newCliffDuration;
        emit CliffDurationUpdated(_newCliffDuration);
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
