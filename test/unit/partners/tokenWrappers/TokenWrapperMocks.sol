// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockTokenPermit } from "../../../../contracts/mock/MockTokenPermit.sol";

/// @dev Mock contract to simulate the Distributor
contract MockDistributor {
    IERC20 public wrapper;

    function setWrapper(address _wrapper) external {
        wrapper = IERC20(_wrapper);
    }

    /// @dev Simulates a transfer from distributor (e.g., during claim)
    function simulateClaim(address to, uint256 amount) external {
        wrapper.transfer(to, amount);
    }

    /// @dev Allow receiving ETH (needed for NativeTokenWrapper tests)
    receive() external payable {}
}

/// @dev Mock contract to simulate fee recipient
contract MockFeeRecipient {
    /// @dev Allow receiving ETH (needed for NativeTokenWrapper tests)
    receive() external payable {}
}

/// @dev Mock contract that cannot receive ETH (no receive/fallback)
contract MockNonPayable {
    // Intentionally no receive or fallback function
}

/// @dev Mock Aave aToken that wraps an underlying asset
contract MockAaveToken is MockTokenPermit {
    address public immutable POOL;
    address public immutable UNDERLYING_ASSET_ADDRESS;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address _pool,
        address _underlying
    ) MockTokenPermit(name_, symbol_, decimals_) {
        POOL = _pool;
        UNDERLYING_ASSET_ADDRESS = _underlying;
    }
}

/// @dev Mock Aave Pool that handles withdraw by burning aTokens and sending underlying
contract MockAavePool {
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        IERC20(asset).transfer(to, amount);
        return amount;
    }
}
