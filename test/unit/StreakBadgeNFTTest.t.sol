// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/StreakBadgeNFT.sol";

// Mock HabitInstance

contract StreakBadgeNFTTest is Test {
    StreakBadgeNFT nft;
    address mockHabit = address(0xabc);

    function setUp() public {
        nft = new StreakBadgeNFT(mockHabit);
    }

    function testMintAndUpdate() public {
        nft.mint(address(this), 1);
        nft.updateStreak(1, 7, false);
        assertEq(uint256(nft.metadata(1).tier), uint256(StreakBadgeNFT.Tier.Copper));
    }

    function testSoulboundTransfer() public {
        nft.mint(address(this), 1);
        vm.expectRevert("Soulbound: non-transferable");
        nft.transferFrom(address(this), address(0xdef), 1);
    }

    // Test tokenURI generation, tiers.
}