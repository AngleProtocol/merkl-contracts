// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";

import { MockToken } from "../../contracts/mock/MockToken.sol";

contract TokensUtils {
    function transferNativeTokens(address recipient, uint256 amount) public virtual {
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Failed to transfer native tokens");
    }

    function transferNativeTokens(address[] memory recipients, uint256[] memory amounts) public virtual {
        require(recipients.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            (bool success, ) = recipients[i].call{ value: amounts[i] }("");
            require(success, "Failed to transfer native tokens");
        }
    }

    function transferERC20Tokens(address recipient, uint256 amount, address token) public virtual {
        MockToken(token).transfer(recipient, amount);
    }

    function transferERC20Tokens(address[] memory recipients, uint256[] memory amounts, address token) public virtual {
        require(recipients.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            MockToken(token).transfer(recipients[i], amounts[i]);
        }
    }

    function mintERC20Tokens(address recipient, uint256 amount, address token) public virtual {
        MockToken(token).mint(recipient, amount);
    }

    function mintERC20Tokens(address[] memory recipients, uint256[] memory amounts, address token) public virtual {
        require(recipients.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            MockToken(token).mint(recipients[i], amounts[i]);
        }
    }
}
