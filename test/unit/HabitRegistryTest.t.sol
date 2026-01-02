// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/HabitRegistry.sol";

contract HabitRegistryTest is Test {
    HabitRegistry registry;
    address owner = address(this);

    function setUp() public {
        registry = new HabitRegistry();
    }

    function testRegister() public {
        registry.register(address(0x1), 1, address(0), 1e18);
        uint256[] memory habits = registry.userHabits(address(0x1));
        assertEq(habits[0], 1);
        assertEq(registry.totalHabits(), 1);
        assertEq(registry.totalStakeETH(), 1e18);
    }

    // Add more unit tests for edge cases, reverts, etc.
}