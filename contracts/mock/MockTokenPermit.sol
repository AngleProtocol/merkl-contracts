// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTokenPermit is ERC20Permit {
    using SafeERC20 for IERC20;
    event Minting(address indexed _to, address indexed _minter, uint256 _amount);

    event Burning(address indexed _from, address indexed _burner, uint256 _amount);

    uint8 internal _decimal;
    mapping(address => bool) public minters;
    address public treasury;
    uint256 public fees;

    bool public reverts;

    constructor(string memory name_, string memory symbol_, uint8 decimal_) ERC20Permit(name_) ERC20(name_, symbol_) {
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

    function setFees(uint256 _fees) public {
        fees = _fees;
    }

    function recoverERC20(IERC20 token, address to, uint256 amount) external {
        token.safeTransfer(to, amount);
    }

    function swapIn(address bridgeToken, uint256 amount, address to) external returns (uint256) {
        require(!reverts);

        IERC20(bridgeToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 canonicalOut = amount;
        canonicalOut -= (canonicalOut * fees) / 10 ** 9;
        _mint(to, canonicalOut);
        return canonicalOut;
    }

    function swapOut(address bridgeToken, uint256 amount, address to) external returns (uint256) {
        require(!reverts);
        _burn(msg.sender, amount);
        uint256 bridgeOut = amount;
        bridgeOut -= (bridgeOut * fees) / 10 ** 9;
        IERC20(bridgeToken).safeTransfer(to, bridgeOut);
        return bridgeOut;
    }
}
