// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    event Minting(address indexed _to, address indexed _minter, uint256 _amount);

    event Burning(address indexed _from, address indexed _burner, uint256 _amount);

    uint8 internal _decimal;
    mapping(address => bool) public minters;
    address public treasury;

    constructor(string memory name_, string memory symbol_, uint8 decimal_) ERC20(name_, symbol_) {
        _decimal = decimal_;
    }

    function decimals() public view override returns (uint8) {
        return _decimal;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
        emit Minting(account, msg.sender, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
        emit Burning(account, msg.sender, amount);
    }

    function setAllowance(address from, address to) public {
        _approve(from, to, type(uint256).max);
    }

    function burnSelf(uint256 amount, address account) public {
        _burn(account, amount);
        emit Burning(account, msg.sender, amount);
    }

    function addMinter(address minter) public {
        minters[minter] = true;
    }

    function removeMinter(address minter) public {
        minters[minter] = false;
    }

    function setTreasury(address _treasury) public {
        treasury = _treasury;
    }
}
