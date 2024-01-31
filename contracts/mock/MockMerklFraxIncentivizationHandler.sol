// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "../middleman/MerklFraxIncentivizationHandler.sol";

contract MockMerklFraxIncentivizationHandler is MerklFraxIncentivizationHandler {
    DistributionCreator public manager;

    constructor(address _operator) MerklFraxIncentivizationHandler(_operator) {}

    function merklDistributionCreator() public view override returns (DistributionCreator) {
        return manager;
    }

    function setAddresses(DistributionCreator _manager) external {
        manager = _manager;
    }
}
