// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Fixture.s.sol";

contract DistributionCreatorOOGTest is Fixture {
    using SafeERC20 for IERC20;

    uint256 startTime;

    function setUp() public override {
        super.setUp();

        startTime = block.timestamp;

        vm.startPrank(guardian);
        creator.toggleSigningWhitelist(alice);
        creator.toggleTokenWhitelist(address(agEUR));
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(angle);
        amounts[0] = 1e18;
        creator.setRewardTokenMinAmounts(tokens, amounts);
        vm.stopPrank();

        angle.mint(address(alice), 1e22);
        vm.prank(alice);
        angle.approve(address(creator), type(uint256).max);
    }
}
