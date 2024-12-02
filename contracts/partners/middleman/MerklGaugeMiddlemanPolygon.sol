// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { MerklGaugeMiddleman, IAccessControlManager, IERC20 } from "./MerklGaugeMiddleman.sol";

/// @title MerklGaugeMiddlemanPolygon
/// @author Angle Labs, Inc.
contract MerklGaugeMiddlemanPolygon is MerklGaugeMiddleman {
    constructor(IAccessControlManager _accessControlManager) MerklGaugeMiddleman(_accessControlManager) {}

    function angle() public pure override returns (IERC20) {
        return IERC20(0x900F717EA076E1E7a484ad9DD2dB81CEEc60eBF1);
    }
}
