// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/HabitRegistry.sol";
import "../../src/HabitInstance.sol";
import "../../src/RewardVault.sol";
import "../../src/StreakBadgeNFT.sol";

// Mock priceFeed

contract FullFlowTest is Test {
    HabitRegistry registry;
    HabitInstance habit;
    RewardVault vault;
    StreakBadgeNFT nft;

    function setUp() public {
        registry = new HabitRegistry();
        habit = new HabitInstance(address(this), address(0xusdc), address(0xprice), address(registry));
        vault = new RewardVault(address(habit));
        nft = new StreakBadgeNFT(address(habit));
        habit.setRewardVault(address(vault));
        habit.setNFT(address(nft));
    }

    function testCreateCheckInClaim() public {
        // Create habit
        vm.deal(address(this), 1 ether);
        habit.createHabit{value: 0.003 ether}("Test", HabitInstance.Frequency.Daily, 7, address(0), 0.003 ether, false, 0, 23 hours);

        // Simulate 7 check-ins
        for (uint i = 0; i < 7; i++) {
            vm.warp(block.timestamp + 24 hours);
            habit.checkIn(1);
        }

        // Claim rewards (initially 0)
        habit.claimRewards(1);

        // Simulate miss
        vm.warp(block.timestamp + 48 hours + 1);
        habit.breakStreak(1);

        // Restart, etc.
    }

    // Add multi-user, addStake reset, edit no reset, penalty dist.
}