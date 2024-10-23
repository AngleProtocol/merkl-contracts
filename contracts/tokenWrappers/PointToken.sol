// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICore } from "../interfaces/ICore.sol";
import "../utils/Errors.sol";

/// @title PointToken
/// @author Angle Labs, Inc.
/// @notice Reference contract for points systems within Merkl
contract PointToken is ERC20 {
    mapping(address => bool) public minters;
    mapping(address => bool) public whitelistedRecipients;
    ICore public accessControlManager;
    uint8 public allowedTransfers;

    constructor(
        string memory name_,
        string memory symbol_,
        address _minter,
        address _accessControlManager
    ) ERC20(name_, symbol_) {
        if (_accessControlManager == address(0) || _minter == address(0)) revert ZeroAddress();
        accessControlManager = ICore(_accessControlManager);
        minters[_minter] = true;
    }

    modifier onlyGovernorOrGuardian() {
        if (!accessControlManager.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    modifier onlyMinter() {
        if (!minters[msg.sender]) revert NotTrusted();
        _;
    }

    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyMinter {
        _burn(account, amount);
    }

    function mintBatch(address[] memory accounts, uint256[] memory amounts) external onlyMinter {
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length; ++i) {
            _mint(accounts[i], amounts[i]);
        }
    }

    function toggleMinter(address minter) external onlyGovernorOrGuardian {
        minters[minter] = !minters[minter];
    }

    function toggleAllowedTransfers() external onlyGovernorOrGuardian {
        allowedTransfers = 1 - allowedTransfers;
    }

    function toggleWhitelistedRecipient(address recipient) external onlyGovernorOrGuardian {
        whitelistedRecipients[recipient] = !whitelistedRecipients[recipient];
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        if (
            allowedTransfers == 0 &&
            from != address(0) &&
            to != address(0) &&
            !whitelistedRecipients[from] &&
            !whitelistedRecipients[to]
        ) revert NotAllowed();
    }
}
