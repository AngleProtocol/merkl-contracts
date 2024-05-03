// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC4626, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

// Cooldown logic forked from: https://github.com/aave/aave-stake-v2/blob/master/contracts/stake/StakedTokenV3.sol
contract StakedToken is ERC4626 {
    uint256 public immutable COOLDOWN_SECONDS;
    uint256 public immutable UNSTAKE_WINDOW;

    mapping(address => uint256) public stakerCooldown;

    error InsufficientCooldown();
    error InvalidBalanceOnCooldown();
    error UnstakeWindowFinished();

    event Cooldown(address indexed sender, uint256 timestamp);

    // ================================= FUNCTIONS =================================

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 cooldownSeconds,
        uint256 unstakeWindow
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        COOLDOWN_SECONDS = cooldownSeconds;
        UNSTAKE_WINDOW = unstakeWindow;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(0)) {
            // For a mint: we update the cooldown of the receiver if needed
            stakerCooldown[to] = getNextCooldownTimestamp(0, amount, to, balanceOf(to));
        } else if (to == address(0)) {
            uint256 cooldownEndTimestamp = stakerCooldown[from] + COOLDOWN_SECONDS;
            if (block.timestamp > cooldownEndTimestamp) revert InsufficientCooldown();
            if (block.timestamp - cooldownEndTimestamp <= UNSTAKE_WINDOW) revert UnstakeWindowFinished();
        } else if (from != to) {
            uint256 previousSenderCooldown = stakerCooldown[from];
            stakerCooldown[to] = getNextCooldownTimestamp(previousSenderCooldown, amount, to, balanceOf(to));
            // if cooldown was set and whole balance of sender was transferred - clear cooldown
            if (balanceOf(from) == amount && previousSenderCooldown != 0) {
                stakerCooldown[from] = 0;
            }
        }
    }

    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) public view returns (uint256 toCooldownTimestamp) {
        toCooldownTimestamp = stakerCooldown[toAddress];
        if (toCooldownTimestamp == 0) return 0;

        uint256 minimalValidCooldownTimestamp = block.timestamp - COOLDOWN_SECONDS - UNSTAKE_WINDOW;

        if (minimalValidCooldownTimestamp > toCooldownTimestamp) {
            toCooldownTimestamp = 0;
        } else {
            fromCooldownTimestamp = (minimalValidCooldownTimestamp > fromCooldownTimestamp)
                ? block.timestamp
                : fromCooldownTimestamp;

            if (fromCooldownTimestamp >= toCooldownTimestamp) {
                toCooldownTimestamp =
                    (amountToReceive * fromCooldownTimestamp + toBalance * toCooldownTimestamp) /
                    (amountToReceive + toBalance);
            }
        }
    }

    function cooldown() external {
        if (balanceOf(msg.sender) != 0) revert InvalidBalanceOnCooldown();
        stakerCooldown[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender, block.timestamp);
    }
}
