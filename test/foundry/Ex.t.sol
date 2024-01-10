pragma solidity ^0.8.13;

import { Test, stdError } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

interface testInterface {
    function change_gauge_weight(address addr, uint256 weight) external;

    function change_type_weight(int128 typeid, uint256 weight) external;

    function admin() external view returns (address);

    function gauge_relative_weight(address gauge, uint256 time) external view returns (uint256);

    function gauges(uint256 index) external view returns (address);

    function n_gauges() external view returns (int128);

    function checkpoint() external;

    function time_total() external view returns (uint256);

    function points_total(uint256 time) external view returns (uint256);

    function get_total_weight() external view returns (uint256);

    function get_gauge_weight(address addr) external view returns (uint256);

    function checkpoint_gauge(address addr) external;

    function gauge_relative_weight_write(address addr) external returns (uint256);

    function gauge_relative_weight(address addr) external view returns (uint256);

    function gauge_types(address addr) external view returns (int128);

    function get_type_weight(int128 t) external view returns (uint256);
}

contract PoC is Test {
    function test() public virtual {
        testInterface gc = testInterface(address(0x9aD7e7b0877582E14c17702EecF49018DD6f2367));
        //change weight to zero
        address admin = gc.admin();
        vm.startPrank(admin);
        gc.change_type_weight(int128(1), uint256(0));
        //skip time, 1 month
        skip(3_000_000);
        gc.checkpoint();

        uint totalWeight;
        uint numGauges = uint256(int256(gc.n_gauges()));
        for (uint i = 0; i < numGauges; i++) {
            address g = gc.gauges(i);
            gc.checkpoint_gauge(g);
            totalWeight += gc.get_gauge_weight(g) * gc.get_type_weight(gc.gauge_types(g));
        }
        console.log(totalWeight);
        console.log(gc.get_total_weight());
        assert(totalWeight == gc.get_total_weight());
    }
}
