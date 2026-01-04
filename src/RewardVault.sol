// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHabitInstance {
    function getToken(uint256 habitId) external view returns (address);
    function getOwner(uint256 habitId) external view returns (address);
}

/**
 * @title RewardVault
 * @dev Manages penalty distributions as rewards weighted by streak tiers.
 */
contract RewardVault is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IHabitInstance public habitInstance;

    struct VaultState {
        uint256 rewardPerWeight;
        uint256 totalWeight;
    }

    struct HabitReward {
        uint256 pending;
        uint256 rewardPerWeightPaid;
        uint256 weight;
    }

    mapping(address => VaultState) public vaultStates; // token => VaultState
    mapping(address => mapping(uint256 => HabitReward)) public habitRewards; // token => habitId => HabitReward

    event RewardAdded(address indexed token, uint256 amount);
    event WeightUpdated(uint256 indexed habitId, uint256 newWeight);
    event RewardsClaimed(uint256 indexed habitId, address indexed owner, uint256 amount);

    constructor(address _habitInstance) {
        habitInstance = IHabitInstance(_habitInstance);
    }

    /**
     * @dev Add reward from penalties.
     */
    function addReward(address token, uint256 amount) external {
        VaultState storage v = vaultStates[token];
        if (v.totalWeight > 0) {
            v.rewardPerWeight += (amount * 1e18) / v.totalWeight;
        }
        emit RewardAdded(token, amount);
    }

    /**
     * @dev Update habit weight when tier changes.
     */
    function updateWeight(uint256 habitId, uint256 newWeight) external {
        address token = habitInstance.getToken(habitId);
        HabitReward storage hr = habitRewards[token][habitId];
        accrue(habitId, token);
        vaultStates[token].totalWeight -= hr.weight;
        hr.weight = newWeight;
        vaultStates[token].totalWeight += newWeight;
        emit WeightUpdated(habitId, newWeight);
    }

    /**
     * @dev Claim rewards for a habit.
     */
    function claimRewards(uint256 habitId) external nonReentrant {
        address token = habitInstance.getToken(habitId);
        address owner = habitInstance.getOwner(habitId);
        require(msg.sender == owner, "Not owner");

        accrue(habitId, token);
        HabitReward storage hr = habitRewards[token][habitId];
        uint256 amount = hr.pending;
        hr.pending = 0;

        if (amount > 0) {
            _transferOut(token, owner, amount);
            emit RewardsClaimed(habitId, owner, amount);
        }
    }

    function accrue(uint256 habitId, address token) internal {
        HabitReward storage hr = habitRewards[token][habitId];
        VaultState storage v = vaultStates[token];
        hr.pending += (hr.weight * (v.rewardPerWeight - hr.rewardPerWeightPaid)) / 1e18;
        hr.rewardPerWeightPaid = v.rewardPerWeight;
    }

    function _transferOut(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool sent,) = to.call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}