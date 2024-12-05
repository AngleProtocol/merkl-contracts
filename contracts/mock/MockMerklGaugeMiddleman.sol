// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "../partners/middleman/MerklGaugeMiddleman.sol";

contract MockMerklGaugeMiddleman is MerklGaugeMiddleman {
    address public angleDistributorAddress;
    IERC20 public angleAddress;
    DistributionCreator public manager;

    constructor(IAccessControlManager _coreBorrow) MerklGaugeMiddleman(_coreBorrow) {}

    function angle() public view override returns (IERC20) {
        return angleAddress;
    }

    function merklDistributionCreator() public view override returns (DistributionCreator) {
        return manager;
    }

    function setAddresses(
        address _angleDistributorAddress,
        IERC20 _angleAddress,
        DistributionCreator _manager
    ) external {
        angleDistributorAddress = _angleDistributorAddress;
        angleAddress = _angleAddress;
        manager = _manager;
    }
}
