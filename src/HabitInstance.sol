// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IRewardVault {
    function addReward(address token, uint256 amount) external;
    function updateWeight(uint256 habitId, uint256 newWeight) external;
    function claimRewards(uint256 habitId) external;
}

interface IStreakBadgeNFT {
    function mint(address to, uint256 habitId) external;
    function updateStreak(uint256 habitId, uint256 streak, bool isBreak) external;
}

interface IHabitRegistry {
    function register(address owner, uint256 habitId, address token, uint256 stake) external;
    function updateStakeDelta(address token, int256 delta) external;
}

/**
 * @title HabitInstance
 * @dev Manages individual habit instances, stakes, check-ins, and penalties.
 * Note: Weekdays frequency and time window are simplified to daily with cooldown for this implementation.
 * Extend for full weekdays logic if needed.
 */
contract HabitInstance is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    address public treasury;
    address public usdc;
    AggregatorV3Interface public priceFeed;
    IRewardVault public rewardVault;
    IStreakBadgeNFT public nft;
    IHabitRegistry public registry;

    uint256 public nextHabitId = 1;
    uint256 constant GRACE_PERIOD = 24 hours;
    uint256 constant PENALTY_RATE = 2; // 2%
    uint256 constant MIN_USD = 1;

    enum Frequency { Daily, Weekdays }

    struct Habit {
        string name;
        address owner;
        Frequency frequency;
        uint256 duration; // 0 for open-ended
        address token; // address(0) for ETH, usdc for USDC
        uint256 stake;
        uint256 currentStreak;
        uint256 lastCheckIn;
        uint256 createdAt;
        bool isPrivate;
        bytes32 commitmentHash;
        uint256 cooldown; // e.g., 23 hours
    }

    mapping(uint256 => Habit) public habits;

    event HabitCreated(uint256 indexed habitId, address indexed owner, string name);
    event CheckIn(uint256 indexed habitId, uint256 newStreak);
    event StreakBroken(uint256 indexed habitId, uint256 penaltyAmount);
    event StakeAdded(uint256 indexed habitId, uint256 amount);
    event StakeEdited(uint256 indexed habitId, uint256 newStake);
    event RewardsClaimed(uint256 indexed habitId, uint256 amount);

    constructor(address _treasury, address _usdc, address _priceFeed, address _registry) Ownable2Step() {
        treasury = _treasury;
        usdc = _usdc;
        priceFeed = AggregatorV3Interface(_priceFeed);
        registry = IHabitRegistry(_registry);
    }

    function setRewardVault(address _rewardVault) external onlyOwner {
        rewardVault = IRewardVault(_rewardVault);
    }

    function setNFT(address _nft) external onlyOwner {
        nft = IStreakBadgeNFT(_nft);
    }

    /**
     * @dev Create a new habit.
     */
    function createHabit(string memory name, Frequency frequency, uint256 duration, address token, uint256 stakeAmount, bool isPrivate, bytes32 commitmentHash, uint256 cooldown) external payable whenNotPaused {
        require(isValidDuration(duration), "Invalid duration");
        require(token == address(0) || token == usdc, "Invalid token");
        require(getUSDValue(token, stakeAmount) >= MIN_USD * (token == address(0) ? 1e18 : 1e12), "Stake below minimum");

        if (token == address(0)) {
            require(msg.value == stakeAmount, "Incorrect ETH value");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), stakeAmount);
        }

        uint256 habitId = nextHabitId++;
        Habit memory newHabit = Habit({
            name: name,
            owner: msg.sender,
            frequency: frequency,
            duration: duration,
            token: token,
            stake: stakeAmount,
            currentStreak: 0,
            lastCheckIn: block.timestamp,
            createdAt: block.timestamp,
            isPrivate: isPrivate,
            commitmentHash: commitmentHash,
            cooldown: cooldown
        });
        habits[habitId] = newHabit;

        registry.register(msg.sender, habitId, token, stakeAmount);
        nft.mint(msg.sender, habitId);
        rewardVault.updateWeight(habitId, 0); // Initial weight 0

        emit HabitCreated(habitId, msg.sender, name);
    }

    /**
     * @dev Perform check-in for a habit.
     */
    function checkIn(uint256 habitId) external nonReentrant whenNotPaused {
        Habit storage h = habits[habitId];
        require(msg.sender == h.owner, "Not owner");

        // Check for miss
        if (_hasMissed(h)) {
            _applyPenalty(habitId);
        }

        require(block.timestamp >= h.lastCheckIn + h.cooldown, "Cooldown not met");

        h.currentStreak++;
        h.lastCheckIn = block.timestamp;

        uint256 newWeight = getWeight(h.currentStreak);
        rewardVault.updateWeight(habitId, newWeight);
        nft.updateStreak(habitId, h.currentStreak, false);

        emit CheckIn(habitId, h.currentStreak);
    }

    /**
     * @dev Add stake to habit, resets streak.
     */
    function addStake(uint256 habitId, uint256 amount) external payable nonReentrant whenNotPaused {
        Habit storage h = habits[habitId];
        require(msg.sender == h.owner, "Not owner");

        if (h.token == address(0)) {
            require(msg.value == amount, "Incorrect ETH value");
        } else {
            IERC20(h.token).safeTransferFrom(msg.sender, address(this), amount);
        }

        registry.updateStakeDelta(h.token, int256(amount));
        h.stake += amount;
        h.currentStreak = 0;
        rewardVault.updateWeight(habitId, 0);
        nft.updateStreak(habitId, 0, true); // Treat as break for history

        emit StakeAdded(habitId, amount);
    }

    /**
     * @dev Edit stake amount without reset.
     */
    function editStake(uint256 habitId, uint256 newStake) external nonReentrant whenNotPaused {
        Habit storage h = habits[habitId];
        require(msg.sender == h.owner, "Not owner");
        require(newStake >= h.stake / 2, "Cannot reduce below half"); // Arbitrary rule to prevent abuse

        int256 delta = int256(newStake) - int256(h.stake);
        registry.updateStakeDelta(h.token, delta);

        if (delta > 0) {
            if (h.token == address(0)) {
                require(msg.value == uint256(delta), "Incorrect ETH value");
            } else {
                IERC20(h.token).safeTransferFrom(msg.sender, address(this), uint256(delta));
            }
        } else if (delta < 0) {
            uint256 refund = uint256(-delta);
            _transferOut(h.token, msg.sender, refund);
        }

        h.stake = newStake;

        emit StakeEdited(habitId, newStake);
    }

    /**
     * @dev Claim rewards for habit.
     */
    function claimRewards(uint256 habitId) external nonReentrant whenNotPaused {
        require(msg.sender == habits[habitId].owner, "Not owner");
        rewardVault.claimRewards(habitId);
        emit RewardsClaimed(habitId, 0); // Amount not tracked here
    }

    /**
     * @dev Break streak if missed (permissionless).
     */
    function breakStreak(uint256 habitId) external nonReentrant whenNotPaused {
        if (_hasMissed(habits[habitId])) {
            _applyPenalty(habitId);
        }
    }

    function _hasMissed(Habit storage h) internal view returns (bool) {
        return block.timestamp > h.lastCheckIn + 1 days + GRACE_PERIOD;
    }

    function _applyPenalty(uint256 habitId) internal {
        Habit storage h = habits[habitId];

        // Calculate missed periods (simplified for daily)
        uint256 timeMissed = block.timestamp - h.lastCheckIn - GRACE_PERIOD;
        uint256 missed = timeMissed / 1 days;
        if (missed == 0) return;

        uint256 penaltyAmount = (h.stake * PENALTY_RATE * missed) / 100;
        if (penaltyAmount > h.stake) penaltyAmount = h.stake;

        uint256 half = penaltyAmount / 2;
        _transferOut(h.token, treasury, half);
        _transferOut(h.token, address(rewardVault), penaltyAmount - half);

        rewardVault.addReward(h.token, penaltyAmount - half);

        registry.updateStakeDelta(h.token, -int256(penaltyAmount));
        h.stake -= penaltyAmount;
        h.currentStreak = 0;
        h.lastCheckIn += missed * 1 days; // Update to last possible

        nft.updateStreak(habitId, 0, true);

        emit StreakBroken(habitId, penaltyAmount);
    }

    function _transferOut(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool sent,) = to.call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        if (token == address(0)) {
            (, int256 price,,,) = priceFeed.latestRoundData();
            require(price > 0, "Invalid price");
            return (amount * uint256(price)) / 1e8; // To USD with 18 decimals
        } else {
            return amount / 1e6 * 1e18; // USDC to 18 decimals
        }
    }

    function getWeight(uint256 streak) public pure returns (uint256) {
        if (streak < 7) return 0;
        if (streak < 30) return 1;
        if (streak < 60) return 2;
        if (streak < 100) return 4;
        if (streak < 150) return 8;
        return 16;
    }

    function isValidDuration(uint256 duration) pure internal returns (bool) {
        return duration == 0 || duration == 7 || duration == 30 || duration == 60 || duration == 100 || duration == 150;
    }

    function getToken(uint256 habitId) external view returns (address) {
        return habits[habitId].token;
    }

    function getOwner(uint256 habitId) external view returns (address) {
        return habits[habitId].owner;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}