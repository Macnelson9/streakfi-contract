// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HabitRegistry.sol";
import "../src/HabitInstance.sol";
import "../src/RewardVault.sol";
import "../src/StreakBadgeNFT.sol";

contract Deploy is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        address treasury = msg.sender;
        address usdc;
        address priceFeed;

        if (block.chainid == 8453) { // Base mainnet
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
            priceFeed = 0x71041dddad3595F9CEd3dccfbe3D1F4b0a16Bb70; // ETH/USD
        } else if (block.chainid == 42220) { // Celo mainnet
            usdc = 0xcebA9300f2b948710d0413de3fA54A989bf9B9B0; // Bridged USDC, confirm address
            priceFeed = 0x7A9f34a0aa917D438e9b6E630067062B6F8f6f3D; // ETH/USD, confirm
        } else {
            revert("Unsupported chain");
        }

        HabitRegistry registry = new HabitRegistry();
        HabitInstance habit = new HabitInstance(treasury, usdc, priceFeed, address(registry));
        RewardVault vault = new RewardVault(address(habit));
        StreakBadgeNFT nft = new StreakBadgeNFT(address(habit));

        habit.setRewardVault(address(vault));
        habit.setNFT(address(nft));

        registry.transferOwnership(treasury);
        habit.transferOwnership(treasury);
        vault.transferOwnership(treasury);
        nft.transferOwnership(treasury);

        vm.stopBroadcast();
    }
}