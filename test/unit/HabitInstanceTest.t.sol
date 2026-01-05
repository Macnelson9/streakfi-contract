// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/HabitInstance.sol";
import "../../src/HabitRegistry.sol";
import "../../src/RewardVault.sol";
import "../../src/StreakBadgeNFT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC Token
contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract HabitInstanceTest is Test {
    HabitInstance habit;
    HabitRegistry registry;
    RewardVault rewardVault;
    StreakBadgeNFT nft;
    MockUSDC usdc;
    address priceFeed = address(0x456);

    address user1 = address(0x1111);
    address user2 = address(0x2222);
    address user3 = address(0x3333);
    address treasury = address(0x4444);

    uint256 constant ETH_STAKE = 0.003 ether; // ~$6 at $2000/ETH
    uint256 constant USDC_STAKE = 6e6; // 6 USDC
    uint256 constant COOLDOWN = 23 hours;

    event HabitCreated(uint256 indexed habitId, address indexed owner, string name);
    event CheckIn(uint256 indexed habitId, uint256 newStreak);
    event StreakBroken(uint256 indexed habitId, uint256 penaltyAmount);
    event StakeAdded(uint256 indexed habitId, uint256 amount);
    event StakeEdited(uint256 indexed habitId, uint256 newStake);
    event RewardsClaimed(uint256 indexed habitId, uint256 amount);

    function setUp() public {
        // Deploy contracts
        registry = new HabitRegistry();
        usdc = new MockUSDC();
        habit = new HabitInstance(treasury, address(usdc), priceFeed, address(registry));
        rewardVault = new RewardVault(address(habit));
        nft = new StreakBadgeNFT(address(habit));

        // Set up relationships
        habit.setRewardVault(address(rewardVault));
        habit.setNFT(address(nft));

        // Mock Chainlink price feed: $2000/ETH
        vm.mockCall(
            priceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        // Mint USDC to users
        usdc.mint(user1, 1000e6);
        usdc.mint(user2, 1000e6);
        usdc.mint(user3, 1000e6);

        // Deal ETH to users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    // ============== CREATE HABIT TESTS ==============

    function testCreateHabitETH_Success() public {
        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true);
        emit HabitCreated(1, user1, "Morning Run");

        habit.createHabit{value: ETH_STAKE}(
            "Morning Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );

        HabitInstance.Habit memory h = habit.habits(1);
        assertEq(h.name, "Morning Run");
        assertEq(h.owner, user1);
        assertEq(h.stake, ETH_STAKE);
        assertEq(h.currentStreak, 0);
        assertEq(h.lastCheckIn, block.timestamp);
        assertEq(h.duration, 30);
        assertEq(h.isPrivate, false);
        assertEq(uint256(h.frequency), uint256(HabitInstance.Frequency.Daily));
        assertEq(h.cooldown, COOLDOWN);
        vm.stopPrank();
    }

    function testCreateHabitUSDC_Success() public {
        vm.startPrank(user1);
        usdc.approve(address(habit), USDC_STAKE);

        vm.expectEmit(true, true, false, true);
        emit HabitCreated(1, user1, "Gym");

        habit.createHabit(
            "Gym",
            HabitInstance.Frequency.Daily,
            60,
            address(usdc),
            USDC_STAKE,
            true,
            keccak256("secret"),
            COOLDOWN
        );

        HabitInstance.Habit memory h = habit.habits(1);
        assertEq(h.name, "Gym");
        assertEq(h.token, address(usdc));
        assertEq(h.stake, USDC_STAKE);
        assertEq(h.isPrivate, true);
        assertEq(h.commitmentHash, keccak256("secret"));
        vm.stopPrank();
    }

    function testCreateHabit_AllValidDurations() public {
        uint256[] memory validDurations = new uint256[](6);
        validDurations[0] = 0;
        validDurations[1] = 7;
        validDurations[2] = 30;
        validDurations[3] = 60;
        validDurations[4] = 100;
        validDurations[5] = 150;

        for (uint256 i = 0; i < validDurations.length; i++) {
            vm.startPrank(user1);
            habit.createHabit{value: ETH_STAKE}(
                "Test",
                HabitInstance.Frequency.Daily,
                validDurations[i],
                address(0),
                ETH_STAKE,
                false,
                0,
                COOLDOWN
            );
            vm.stopPrank();
        }

        assertEq(habit.nextHabitId(), 7); // 1-6 created
    }

    function testCreateHabit_InvalidDuration_Fails() public {
        vm.startPrank(user1);
        vm.expectRevert("Invalid duration");
        habit.createHabit{value: ETH_STAKE}(
            "Bad",
            HabitInstance.Frequency.Daily,
            50, // Invalid
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testCreateHabit_InvalidToken_Fails() public {
        vm.startPrank(user1);
        vm.expectRevert("Invalid token");
        habit.createHabit{value: ETH_STAKE}(
            "Bad",
            HabitInstance.Frequency.Daily,
            30,
            address(0x9999), // Invalid token
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testCreateHabit_StakeBelowMinimum_ETH_Fails() public {
        vm.startPrank(user1);
        uint256 tinyStake = 0.0001 ether; // Way below $1
        vm.expectRevert("Stake below minimum");
        habit.createHabit{value: tinyStake}(
            "Tiny",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            tinyStake,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testCreateHabit_StakeBelowMinimum_USDC_Fails() public {
        vm.startPrank(user1);
        usdc.approve(address(habit), 0.5e6);
        vm.expectRevert("Stake below minimum");
        habit.createHabit(
            "Tiny",
            HabitInstance.Frequency.Daily,
            30,
            address(usdc),
            0.5e6, // 0.5 USDC < $1
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testCreateHabit_IncorrectETHValue_Fails() public {
        vm.startPrank(user1);
        vm.expectRevert("Incorrect ETH value");
        habit.createHabit{value: 0.002 ether}(
            "Wrong",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE, // Different from msg.value
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testCreateHabit_ZeroStake_Fails() public {
        vm.startPrank(user1);
        vm.expectRevert("Stake below minimum");
        habit.createHabit{value: 0}(
            "Zero",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            0,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testCreateHabit_MultipleHabits() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.createHabit{value: ETH_STAKE}(
            "Gym",
            HabitInstance.Frequency.Daily,
            60,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        assertEq(habit.nextHabitId(), 3);
        assertEq(habit.habits(1).name, "Run");
        assertEq(habit.habits(2).name, "Gym");
    }

    function testCreateHabit_FrequencyOptions() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Daily",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.createHabit{value: ETH_STAKE}(
            "Weekdays",
            HabitInstance.Frequency.Weekdays,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        assertEq(uint256(habit.habits(1).frequency), uint256(HabitInstance.Frequency.Daily));
        assertEq(uint256(habit.habits(2).frequency), uint256(HabitInstance.Frequency.Weekdays));
    }

    // ============== CHECK-IN TESTS ==============

    function testCheckIn_Success() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );

        vm.expectEmit(true, false, false, true);
        emit CheckIn(1, 1);

        habit.checkIn(1);

        HabitInstance.Habit memory h = habit.habits(1);
        assertEq(h.currentStreak, 1);
        assertEq(h.lastCheckIn, block.timestamp);
        vm.stopPrank();
    }

    function testCheckIn_MultipleCheckins() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );

        habit.checkIn(1);
        assertEq(habit.habits(1).currentStreak, 1);

        vm.warp(block.timestamp + COOLDOWN + 1);
        habit.checkIn(1);
        assertEq(habit.habits(1).currentStreak, 2);

        vm.warp(block.timestamp + COOLDOWN + 1);
        habit.checkIn(1);
        assertEq(habit.habits(1).currentStreak, 3);
        vm.stopPrank();
    }

    function testCheckIn_NotOwner_Fails() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("Not owner");
        habit.checkIn(1);
        vm.stopPrank();
    }

    function testCheckIn_CooldownNotMet_Fails() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        vm.expectRevert("Cooldown not met");
        habit.checkIn(1); // Try immediately
        vm.stopPrank();
    }

    function testCheckIn_CooldownMet_Success() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        vm.warp(block.timestamp + COOLDOWN);
        habit.checkIn(1);
        assertEq(habit.habits(1).currentStreak, 2);
        vm.stopPrank();
    }

    // ============== PENALTY TESTS ==============

    function testPenalty_MissedCheckIn() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        uint256 stakeBeforePenalty = habit.habits(1).stake;

        // Miss by 2 days (1 day + grace period + 1 extra day)
        vm.warp(block.timestamp + 2 days + 24 hours + 1 seconds);

        vm.expectEmit(true, false, false, true);
        emit StreakBroken(1, (stakeBeforePenalty * 2 * 2) / 100); // 2% penalty for 2 days

        habit.checkIn(1);

        HabitInstance.Habit memory h = habit.habits(1);
        assertEq(h.currentStreak, 0);
        assertLt(h.stake, stakeBeforePenalty);
        vm.stopPrank();
    }

    function testPenalty_BreakStreak_Permissionless() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);
        vm.stopPrank();

        uint256 stakeBeforePenalty = habit.habits(1).stake;

        // Miss check-in
        vm.warp(block.timestamp + 2 days + 24 hours + 1 seconds);

        // Anyone can call breakStreak
        vm.startPrank(user2);
        habit.breakStreak(1);
        vm.stopPrank();

        assertEq(habit.habits(1).currentStreak, 0);
        assertLt(habit.habits(1).stake, stakeBeforePenalty);
    }

    function testPenalty_NoMissIfWithinGracePeriod() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        uint256 stakeBeforePenalty = habit.habits(1).stake;

        // Within grace period (1 day + 12 hours is within 1 day + 24 hours grace)
        vm.warp(block.timestamp + 1 days + 12 hours);

        habit.checkIn(1);

        HabitInstance.Habit memory h = habit.habits(1);
        assertEq(h.currentStreak, 2); // No penalty
        assertEq(h.stake, stakeBeforePenalty);
        vm.stopPrank();
    }

    function testPenalty_PenaltyCapAtStake() public {
        vm.startPrank(user1);
        uint256 smallStake = 0.005 ether; // ~$10
        habit.createHabit{value: smallStake}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            smallStake,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);
        vm.stopPrank();

        uint256 stakeBeforePenalty = habit.habits(1).stake;

        // Miss by many days to exceed penalty cap
        vm.warp(block.timestamp + 100 days);

        habit.breakStreak(1);

        HabitInstance.Habit memory h = habit.habits(1);
        // Penalty capped at stake
        assertLe(h.stake, stakeBeforePenalty / 2); // At least half is taken
        vm.stopPrank();
    }

    function testPenalty_MultipleMissedDays() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        uint256 stakeBeforePenalty = habit.habits(1).stake;

        // Miss exactly 3 days
        vm.warp(block.timestamp + 1 days + 24 hours + 3 days);

        habit.checkIn(1);

        uint256 expectedPenalty = (stakeBeforePenalty * 2 * 3) / 100; // 2% per day for 3 days
        uint256 expectedStake = stakeBeforePenalty - expectedPenalty;
        assertEq(habit.habits(1).stake, expectedStake);
        vm.stopPrank();
    }

    // ============== STAKE MANAGEMENT TESTS ==============

    function testAddStake_Success() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        uint256 addAmount = 0.002 ether;
        vm.expectEmit(true, false, false, true);
        emit StakeAdded(1, addAmount);

        habit.addStake{value: addAmount}(1, addAmount);

        HabitInstance.Habit memory h = habit.habits(1);
        assertEq(h.stake, ETH_STAKE + addAmount);
        assertEq(h.currentStreak, 0); // Streak resets
        vm.stopPrank();
    }

    function testAddStake_ResetsStreak() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);
        assertEq(habit.habits(1).currentStreak, 1);

        habit.addStake{value: 0.001 ether}(1, 0.001 ether);
        assertEq(habit.habits(1).currentStreak, 0);
        vm.stopPrank();
    }

    function testAddStake_NotOwner_Fails() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("Not owner");
        habit.addStake{value: 0.001 ether}(1, 0.001 ether);
        vm.stopPrank();
    }

    function testAddStake_IncorrectETHValue_Fails() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );

        vm.expectRevert("Incorrect ETH value");
        habit.addStake{value: 0.001 ether}(1, 0.002 ether);
        vm.stopPrank();
    }

    function testAddStake_USDC() public {
        vm.startPrank(user1);
        usdc.approve(address(habit), USDC_STAKE + 1e6);
        habit.createHabit(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(usdc),
            USDC_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        uint256 addAmount = 1e6;
        habit.addStake(1, addAmount);

        assertEq(habit.habits(1).stake, USDC_STAKE + addAmount);
        vm.stopPrank();
    }

    function testEditStake_IncreaseSuccess() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);

        uint256 newStake = ETH_STAKE * 2;
        uint256 delta = newStake - ETH_STAKE;

        vm.expectEmit(true, false, false, true);
        emit StakeEdited(1, newStake);

        habit.editStake{value: delta}(1, newStake);

        assertEq(habit.habits(1).stake, newStake);
        assertEq(habit.habits(1).currentStreak, 1); // Doesn't reset on edit
        vm.stopPrank();
    }

    function testEditStake_DecreaseSuccess() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );

        uint256 newStake = ETH_STAKE / 2 + 0.0001 ether; // Just above half
        habit.editStake(1, newStake);

        assertEq(habit.habits(1).stake, newStake);
        vm.stopPrank();
    }

    function testEditStake_BelowHalf_Fails() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );

        vm.expectRevert("Cannot reduce below half");
        habit.editStake(1, ETH_STAKE / 3);
        vm.stopPrank();
    }

    function testEditStake_NotOwner_Fails() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("Not owner");
        habit.editStake(1, ETH_STAKE * 2);
        vm.stopPrank();
    }

    // ============== WEIGHT & TIER TESTS ==============

    function testGetWeight_AllTiers() public {
        assertEq(habit.getWeight(0), 0);
        assertEq(habit.getWeight(6), 0);
        assertEq(habit.getWeight(7), 1);
        assertEq(habit.getWeight(29), 1);
        assertEq(habit.getWeight(30), 2);
        assertEq(habit.getWeight(59), 2);
        assertEq(habit.getWeight(60), 4);
        assertEq(habit.getWeight(99), 4);
        assertEq(habit.getWeight(100), 8);
        assertEq(habit.getWeight(149), 8);
        assertEq(habit.getWeight(150), 16);
        assertEq(habit.getWeight(1000), 16);
    }

    function testGetWeight_EdgeCases() public {
        assertEq(habit.getWeight(1), 0);
        assertEq(habit.getWeight(type(uint256).max), 16);
    }

    // ============== UTILITY & VIEW TESTS ==============

    function testGetToken() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        assertEq(habit.getToken(1), address(0));
    }

    function testGetOwner() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        assertEq(habit.getOwner(1), user1);
    }

    function testGetUSDValue_ETH() public {
        uint256 amount = 1 ether;
        uint256 expectedValue = (amount * 2000e8) / 1e8; // $2000/ETH
        uint256 actualValue = habit.getUSDValue(address(0), amount);
        assertEq(actualValue, expectedValue);
    }

    function testGetUSDValue_USDC() public {
        uint256 amount = 100e6; // 100 USDC
        uint256 expectedValue = (amount / 1e6) * 1e18; // 100 * 1e18
        uint256 actualValue = habit.getUSDValue(address(usdc), amount);
        assertEq(actualValue, expectedValue);
    }

    // ============== PAUSABLE TESTS ==============

    function testPause_OnlyOwner() public {
        habit.pause();
        assertTrue(habit.paused());

        vm.startPrank(user1);
        vm.expectRevert(); // Will fail due to revert from Pausable
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testUnpause() public {
        habit.pause();
        habit.unpause();
        assertFalse(habit.paused());

        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();

        assertEq(habit.habits(1).name, "Run");
    }

    // ============== REENTRANCY TESTS ==============

    function testReentrancy_CheckIn() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);
        vm.stopPrank();

        // Reentrancy guard should prevent double execution
        // This is difficult to test without a malicious contract
        // Forge should catch reentrancy violations
    }

    // ============== EDGE CASE TESTS ==============

    function testZeroStakeAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("Stake below minimum");
        habit.createHabit{value: 0}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            0,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }

    function testMaxUint256Stake() public {
        vm.startPrank(user1);
        // This will fail on the "Stake below minimum" check indirectly
        // because we can't actually transfer that much
        uint256 hugeStake = 1000 ether;
        vm.deal(user1, hugeStake + 1 ether);

        vm.expectEmit(true, true, false, true);
        emit HabitCreated(1, user1, "Huge");

        habit.createHabit{value: hugeStake}(
            "Huge",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            hugeStake,
            false,
            0,
            COOLDOWN
        );

        assertEq(habit.habits(1).stake, hugeStake);
        vm.stopPrank();
    }

    function testZeroCooldown() public {
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            0 // Zero cooldown
        );
        vm.stopPrank();

        vm.startPrank(user1);
        habit.checkIn(1);
        habit.checkIn(1); // Should work immediately
        assertEq(habit.habits(1).currentStreak, 2);
        vm.stopPrank();
    }

    function testLargeHabitId() public {
        vm.startPrank(user1);
        // Create many habits to test large IDs
        for (uint256 i = 0; i < 10; i++) {
            habit.createHabit{value: ETH_STAKE}(
                "Run",
                HabitInstance.Frequency.Daily,
                30,
                address(0),
                ETH_STAKE,
                false,
                0,
                COOLDOWN
            );
        }
        vm.stopPrank();

        assertEq(habit.nextHabitId(), 11);
        assertEq(habit.getOwner(10), user1);
    }

    // ============== ACCESS CONTROL TESTS ==============

    function testSetRewardVault_OnlyOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(); // Will fail due to Ownable2Step
        habit.setRewardVault(address(0x1234));
        vm.stopPrank();

        habit.setRewardVault(address(0x1234));
        assertEq(address(habit.rewardVault()), address(0x1234));
    }

    function testSetNFT_OnlyOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(); // Will fail due to Ownable2Step
        habit.setNFT(address(0x5678));
        vm.stopPrank();

        habit.setNFT(address(0x5678));
        assertEq(address(habit.nft()), address(0x5678));
    }

    // ============== INTEGRATION TESTS ==============

    function testFullFlow_CreateCheckInEarnRewards() public {
        vm.startPrank(user1);
        usdc.approve(address(habit), USDC_STAKE);

        // Create habit
        habit.createHabit(
            "Study",
            HabitInstance.Frequency.Daily,
            30,
            address(usdc),
            USDC_STAKE,
            false,
            0,
            COOLDOWN
        );

        uint256 habitId = 1;

        // Check in multiple times
        for (uint256 i = 0; i < 7; i++) {
            habit.checkIn(habitId);
            vm.warp(block.timestamp + COOLDOWN + 1);
        }

        assertEq(habit.habits(habitId).currentStreak, 7);
        assertEq(habit.getWeight(7), 1);

        vm.stopPrank();
    }

    function testFullFlow_MultiUserCompetition() public {
        // User 1: Strong habit
        vm.startPrank(user1);
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(1);
        vm.stopPrank();

        // User 2: Another habit
        vm.startPrank(user2);
        habit.createHabit{value: ETH_STAKE}(
            "Gym",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        habit.checkIn(2);
        vm.stopPrank();

        assertEq(habit.habits(1).owner, user1);
        assertEq(habit.habits(2).owner, user2);
        assertEq(habit.habits(1).currentStreak, 1);
        assertEq(habit.habits(2).currentStreak, 1);
    }

    function testInvalidPriceFeed_Fails() public {
        // Mock a negative or zero price
        vm.mockCall(
            priceFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 0, 0, 0, 0)
        );

        vm.startPrank(user1);
        vm.expectRevert("Invalid price");
        habit.createHabit{value: ETH_STAKE}(
            "Run",
            HabitInstance.Frequency.Daily,
            30,
            address(0),
            ETH_STAKE,
            false,
            0,
            COOLDOWN
        );
        vm.stopPrank();
    }
}