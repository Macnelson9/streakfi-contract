# Gas Optimization Report

## Overview

- Contracts optimized with packed structs (e.g., bool and uint8 in one slot).
- Use of constants for grace/penalty.
- Avoid unnecessary storage reads/writes.
- No loops in critical paths except for SVG history (capped by practical streak fails).

## Estimated Gas Usage (from tests, placeholders as no execution)

- createHabit: ~150,000 gas
- checkIn (no miss): ~80,000 gas
- breakStreak (with penalty): ~100,000 gas
- claimRewards: ~70,000 gas
- tokenURI: ~50,000 gas (dynamic SVG)

Run ```forge test --gas-report``` for detailed breakdown post-deployment/testing.
Note: Further optimizations possible by slot packing and caching variables.
