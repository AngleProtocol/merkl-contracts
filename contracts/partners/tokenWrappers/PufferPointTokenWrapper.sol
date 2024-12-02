// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseMerklTokenWrapper, IAccessControlManager } from "./BaseTokenWrapper.sol";

import "../../utils/Errors.sol";

struct VestingID {
    uint128 amount;
    uint128 unlockTimestamp;
}

struct VestingData {
    VestingID[] allVestings;
    uint256 nextClaimIndex;
}

/// @title PufferPointTokenWrapper
/// @dev This token can only be held by Merkl distributor
/// @dev Transferring to the distributor will require transferring the underlying token to this contract
/// @dev Transferring from the distributor will trigger a vesting action
/// @dev Transferring token to the distributor is permissionless so anyone could mint this wrapper - the only
/// impact would be to forfeit these tokens
contract PufferPointTokenWrapper is BaseMerklTokenWrapper {
    using SafeERC20 for IERC20;

    // ================================= CONSTANTS =================================

    mapping(address => VestingData) public vestingData;
    uint256 public cliffDuration;
    address public underlying;

    // ================================= FUNCTIONS =================================

    function initializeWrapper(address _underlying, uint256 _cliffDuration, IAccessControlManager _core) public {
        super.initialize(_core);
        if (_underlying == address(0)) revert ZeroAddress();
        underlying = _underlying;
        cliffDuration = _cliffDuration;
    }

    function token() public view override returns (address) {
        return underlying;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Needs an underlying approval beforehand, this is how mints of wrappers are done
        if (to == DISTRIBUTOR) {
            IERC20(underlying).safeTransferFrom(from, address(this), amount);
            _mint(from, amount); // These are then transferred to the distributor
        }

        // Will be burn right after, to avoid having any token aside from on the distributor
        if (to == FEE_RECIPIENT) {
            IERC20(underlying).safeTransferFrom(from, FEE_RECIPIENT, amount);
            _mint(from, amount); // These are then transferred to the fee manager
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (to == FEE_RECIPIENT) {
            _burn(to, amount); // To avoid having any token aside from on the distributor
        }

        if (from == DISTRIBUTOR) {
            _burn(to, amount);
            _createVesting(to, amount);
        }
    }

    function _createVesting(address user, uint256 amount) internal {
        VestingData storage userVestingData = vestingData[user];
        VestingID[] storage userAllVestings = userVestingData.allVestings;
        userAllVestings.push(VestingID(uint128(amount), uint128(block.timestamp + cliffDuration)));
    }

    function claim(address user) external {
        VestingData storage userVestingData = vestingData[user];
        VestingID[] storage userAllVestings = userVestingData.allVestings;
        uint256 i = userVestingData.nextClaimIndex;
        uint256 claimable;
        while (true) {
            VestingID storage userCurrentVesting = userAllVestings[i];
            if (userCurrentVesting.unlockTimestamp > block.timestamp) {
                claimable += userCurrentVesting.amount;
                ++i;
            } else {
                userVestingData.nextClaimIndex = i;
                break;
            }
        }
        IERC20(token()).safeTransfer(user, claimable);
    }

    function getUserVestings(
        address user
    ) external view returns (VestingID[] memory allVestings, uint256 nextClaimIndex) {
        VestingData storage userVestingData = vestingData[user];
        allVestings = userVestingData.allVestings;
        nextClaimIndex = userVestingData.nextClaimIndex;
    }
}
