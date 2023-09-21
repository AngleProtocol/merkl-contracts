// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

contract MockTreasury {
    address public stablecoin;
    address public governor;
    address public guardian;
    address public vaultManager1;
    address public vaultManager2;
    address public flashLoanModule;

    constructor(
        address _stablecoin,
        address _governor,
        address _guardian,
        address _vaultManager1,
        address _vaultManager2,
        address _flashLoanModule
    ) {
        stablecoin = _stablecoin;
        governor = _governor;
        guardian = _guardian;
        vaultManager1 = _vaultManager1;
        vaultManager2 = _vaultManager2;
        flashLoanModule = _flashLoanModule;
    }

    function isGovernor(address admin) external view returns (bool) {
        return (admin == governor);
    }

    function isGovernorOrGuardian(address admin) external view returns (bool) {
        return (admin == governor || admin == guardian);
    }
}
