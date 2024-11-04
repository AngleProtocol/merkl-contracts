// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IDistributionCreator {
    function distributor() external view returns (address);
    function feeRecipient() external view returns (address);
}

contract bscSUNDOG is ERC20, ERC20Permit {
    using SafeERC20 for IERC20;

    IDistributionCreator public constant DISTRIBUTOR_CREATOR =
        IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
    address public immutable DISTRIBUTOR = DISTRIBUTOR_CREATOR.distributor();
    address public immutable MULTISIG = 0x60a48524506cD523B1AAD16c375fc1dB6D01792B;

    error UnauthorizedTransfer();

    constructor() ERC20("bscSUNDOG", "bscSUNDOG") ERC20Permit("bscSUNDOG") {
        _mint(0x60a48524506cD523B1AAD16c375fc1dB6D01792B, 1_000_000_000_000_000_000_000_000_000);
    }

    function _beforeTokenTransfer(address from, address, uint256) internal view override {
        if (from != MULTISIG && from != DISTRIBUTOR && from != address(DISTRIBUTOR_CREATOR) && from != address(0)) {
            revert UnauthorizedTransfer();
        }
    }
}
