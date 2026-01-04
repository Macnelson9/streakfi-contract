// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title HabitRegistry
 * @dev Registry for tracking user habits and global statistics.
 */
contract HabitRegistry is Ownable {

    struct UserHabits {
        uint256[] habitIds;
        uint256 count;
    }

    constructor() Ownable(msg.sender) {}

    mapping(address => UserHabits) public userHabits;
    uint256 public totalHabits;
    uint256 public totalStakeETH;
    uint256 public totalStakeUSDC;

    event HabitCreated(uint256 indexed habitId, address indexed owner);
    event StakeUpdated(uint256 indexed habitId, address indexed token, uint256 newStake);

    /**
     * @dev Register a new habit for a user and update global stats.
     * @param owner The owner of the habit.
     * @param habitId The ID of the habit.
     * @param token The token address (0 for ETH).
     * @param stake The stake amount.
     */
    function register(address owner, uint256 habitId, address token, uint256 stake) external onlyOwner {
        userHabits[owner].habitIds.push(habitId);
        userHabits[owner].count++;
        totalHabits++;
        if (token == address(0)) {
            totalStakeETH += stake;
        } else {
            totalStakeUSDC += stake;
        }
        emit HabitCreated(habitId, owner);
    }

    /**
     * @dev Update stake delta for global stats.
     * @param token The token address.
     * @param delta The change in stake (can be negative).
     */
    function updateStakeDelta(address token, int256 delta) external onlyOwner {
        if (token == address(0)) {
            if (delta > 0) totalStakeETH += uint256(delta);
            else totalStakeETH -= uint256(-delta);
        } else {
            if (delta > 0) totalStakeUSDC += uint256(delta);
            else totalStakeUSDC -= uint256(-delta);
        }
    }

    /**
     * @dev Get habit count for a user.
     * @param user The user address.
     * @return The number of habits for the user.
     */
    function getHabitCount(address user) external view returns (uint256) {
        return userHabits[user].count;
    }

    /**
     * @dev Get habit IDs for a user.
     * @param user The user address.
     * @return Array of habit IDs for the user.
     */
    function getHabitIds(address user) external view returns (uint256[] memory) {
        return userHabits[user].habitIds;
    }
}