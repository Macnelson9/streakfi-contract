// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/HabitInstance.sol";
import "../../src/HabitRegistry.sol";
// Import mocks for Chainlink, etc.

contract HabitInstanceTest is Test {
    HabitInstance habit;
    HabitRegistry registry;
    address usdc = address(0x123);
    address priceFeed = address(0x456); // Mock

    function setUp() public {
        registry = new HabitRegistry();
        habit = new HabitInstance(address(this), usdc, priceFeed, address(registry));
        // Mock priceFeed.latestRoundData to return price 2000e8 for $2000/ETH
        vm.mockCall(priceFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 2000e8, 0, 0, 0));
    }

    function testCreateHabitETH() public {
        uint256 stake = 0.003 ether; // ~$6 at $2000
        vm.deal(address(this), stake);
        habit.createHabit{value: stake}("Run", HabitInstance.Frequency.Daily, 30, address(0), stake, false, 0, 23 hours);
        HabitInstance.Habit memory h = habit.habits(1);
        assertEq(h.stake, stake);
    }

    // Add tests for checkIn, penalties, reverts, zero values, overflow (though 0.8+ safe), access control.
}