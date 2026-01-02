// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IHabitInstance {
    struct Habit {
        string name;
        address owner;
        // ... other fields
    }
    function habits(uint256) external view returns (Habit memory);
}

/**
 * @title StreakBadgeNFT
 * @dev Soulbound ERC721 NFT for habit streaks with onchain dynamic SVG metadata.
 */
contract StreakBadgeNFT is ERC721, Ownable2Step {
    using Strings for uint256;

    IHabitInstance public habitInstance;

    enum Tier { None, Copper, Silver, Sapphire, Gold, Diamond, Platinum }

    struct HabitMetadata {
        uint256 currentStreak;
        uint256[] failedStreaks;
        Tier tier;
    }

    mapping(uint256 => HabitMetadata) public metadata;

    event StreakUpdated(uint256 indexed habitId, uint256 streak, bool isBreak);

    constructor(address _habitInstance) ERC721("StreakBadge", "STREAK") {
        habitInstance = IHabitInstance(_habitInstance);
    }

    function mint(address to, uint256 habitId) external onlyOwner {
        _safeMint(to, habitId);
        metadata[habitId] = HabitMetadata(0, new uint256[](0), Tier.None);
    }

    function updateStreak(uint256 habitId, uint256 streak, bool isBreak) external onlyOwner {
        HabitMetadata storage m = metadata[habitId];
        if (isBreak) {
            m.failedStreaks.push(m.currentStreak);
            m.currentStreak = 0;
        } else {
            m.currentStreak = streak;
        }
        Tier newTier = getTier(streak);
        if (newTier != m.tier) {
            m.tier = newTier;
        }
        emit StreakUpdated(habitId, streak, isBreak);
    }

    function getTier(uint256 streak) public pure returns (Tier) {
        if (streak >= 200) return Tier.Platinum;
        if (streak >= 150) return Tier.Diamond;
        if (streak >= 100) return Tier.Gold;
        if (streak >= 60) return Tier.Sapphire;
        if (streak >= 30) return Tier.Silver;
        if (streak >= 7) return Tier.Copper;
        return Tier.None;
    }

    function getTierString(Tier tier) internal pure returns (string memory) {
        if (tier == Tier.Platinum) return "Platinum";
        if (tier == Tier.Diamond) return "Diamond";
        if (tier == Tier.Gold) return "Gold";
        if (tier == Tier.Sapphire) return "Sapphire";
        if (tier == Tier.Silver) return "Silver";
        if (tier == Tier.Copper) return "Copper";
        return "None";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        IHabitInstance.Habit memory habit = habitInstance.habits(tokenId);
        HabitMetadata memory m = metadata[tokenId];
        string memory habitName = habit.isPrivate ? "Private Habit" : habit.name;
        string memory tierStr = getTierString(m.tier);
        string memory historyStr;
        for (uint i = 0; i < m.failedStreaks.length; i++) {
            historyStr = string(abi.encodePacked(historyStr, m.failedStreaks[i].toString(), i < m.failedStreaks.length - 1 ? ", " : ""));
        }

        string memory svg = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="200" viewBox="0 0 300 200">',
            '<rect width="300" height="200" fill="#f0f0f0"/>',
            '<text x="150" y="50" font-size="20" text-anchor="middle">', tierStr, ' Badge</text>',
            '<text x="150" y="100" font-size="18" text-anchor="middle">Streak: ', m.currentStreak.toString(), '</text>',
            '<text x="150" y="130" font-size="16" text-anchor="middle">Habit: ', habitName, '</text>',
            '<text x="150" y="160" font-size="14" text-anchor="middle">Past: ', historyStr, '</text>',
            '</svg>'
        ));

        string memory json = string(abi.encodePacked(
            '{"name": "Streak Badge #', tokenId.toString(), '", ',
            '"description": "Soulbound NFT for habit streak", ',
            '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '"}'
        ));

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        if (from != address(0)) revert("Soulbound: non-transferable");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}