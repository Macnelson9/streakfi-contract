// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/RewardVault.sol";
import "../../src/HabitInstance.sol";

// Mock HabitInstance for getToken, getOwner

contract RewardVaultTest is Test {
    RewardVault vault;
    address mockHabit = address(0x789);

    function setUp() public {
        vault = new RewardVault(mockHabit);
        vm.mockCall(mockHabit, abi.encodeWithSelector(IHabitInstance.getToken.selector, 1), abi.encode(address(0)));
        vm.mockCall(mockHabit, abi.encodeWithSelector(IHabitInstance.getOwner.selector, 1), abi.encode(address(this)));
    }

    function testAddReward() public {
        vault.addReward(address(0), 1e18);
        // Test logic
    }

    // Add unit tests for updateWeight, claim, reentrancy attempts, etc.
}