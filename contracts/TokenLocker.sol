// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract TokenLocker is Ownable2Step {
    IERC20 public asset;

    uint256 public lockPeriod;
    uint256 public participantNumber;
    uint256 public totalSupply;
    uint256 public constant MAX_LOCK_PERIOD = 60 * 60 * 24 * 180;

    string public name;
    string public symbol;

    mapping(address => uint256) public lockedDeposit;
    mapping(address => uint256) public unlockTime;

    event LockPeriodUpdated(uint256 lockPeriod);
    event Deposit(address depositor, uint256 amount);
    event Withdraw(address caller, address receiver, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    error InvalidDepositAmount();
    error InsufficientLockPeriod();
    error InsufficientDeposit();
    error ZeroAddressReceipient();
    error InvalidLockPeriod();

    modifier onlyValidLockPeriod(uint256 _lockPeriod) {
        if (_lockPeriod > MAX_LOCK_PERIOD) {
            revert InvalidLockPeriod();
        }
        _;
    }

    constructor(
        address _owner,
        IERC20 _asset,
        uint256 _lockPeriod,
        string memory _name,
        string memory _symbol
    ) onlyValidLockPeriod(_lockPeriod) {
        asset = _asset;
        lockPeriod = _lockPeriod;
        name = _name;
        symbol = _symbol;
        _transferOwnership(_owner);
    }

    function updateLockPeriod(uint256 _lockPeriod) external onlyOwner onlyValidLockPeriod(_lockPeriod) {
        lockPeriod = _lockPeriod;

        emit LockPeriodUpdated(_lockPeriod);
    }

    function deposit(uint256 _amount) external {
        if (_amount == 0) {
            revert InvalidDepositAmount();
        }
        if (lockedDeposit[msg.sender] == 0) {
            unchecked {
                ++participantNumber;
            }
        }

        SafeERC20.safeTransferFrom(asset, msg.sender, address(this), _amount);

        lockedDeposit[msg.sender] += _amount;
        unlockTime[msg.sender] = block.timestamp;
        totalSupply += _amount;

        emit Deposit(msg.sender, _amount);
        emit Transfer(address(0), msg.sender, _amount);
    }

    function withdraw(uint256 _amount, address _receiver) external {
        if (_receiver == address(0)) {
            revert ZeroAddressReceipient();
        }
        uint256 userLockedDeposit = lockedDeposit[msg.sender];
        if (userLockedDeposit < _amount) {
            revert InsufficientDeposit();
        }
        if (block.timestamp < getUnlockableTimestamp(msg.sender)) {
            revert InsufficientLockPeriod();
        }
        if ((userLockedDeposit - _amount) == 0) {
            delete unlockTime[msg.sender];
            --participantNumber;
        }

        lockedDeposit[msg.sender] -= _amount;
        totalSupply -= _amount;

        SafeERC20.safeTransfer(asset, _receiver, _amount);

        emit Withdraw(msg.sender, _receiver, _amount);
        emit Transfer(msg.sender, address(0), _amount);
    }

    function getUnlockableTimestamp(address _locker) public view returns (uint256) {
        uint256 unlock = unlockTime[_locker];
        return (unlock == 0) ? 0 : unlock + lockPeriod;
    }

    function decimals() external view returns (uint256) {
        return IERC20Metadata(address(asset)).decimals();
    }

    function balanceOf(address _locker) external view returns (uint256) {
        return lockedDeposit[_locker];
    }
}
