// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract StorageV0 {
    uint256 public a = 0;

    uint256[47] private __gap;
}

contract MockAgEURUpgradeable2 is StorageV0, ERC20, Ownable {
    constructor() ERC20("Mock Token", "MTK") {}

    // ================================= FUNCTIONS =================================

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyOwner {
        _burn(_from, _amount);
    }
}
