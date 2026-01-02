# Security Considerations for StreakFi Contracts

## Reentrancy Risks and Mitigations

- All external calls involving fund transfers use ReentrancyGuard.
- Follow Checks-Effects-Interactions pattern in critical functions like checkIn, breakStreak, claimRewards.
- Tested for reentrancy in unit and integration tests.

## Integer Overflow/Underflow Handling

- Using Solidity ^0.8.20 with built-in overflow checks.
- No manual arithmetic that could overflow; stakes and penalties use safe calculations (e.g., mul/div order to avoid underflow).

## Access Control Model

- Ownable2Step for ownership transfers.
- Function access: User functions restricted to habit owners via require checks.
- Admin functions (set addresses, pause) restricted to owner.
- No additional roles; keep simple.

## Upgrade Path Considerations

- Contracts are not upgradable by default (no proxy).
- For future upgrades, consider implementing UUPS proxy pattern.
- Immutable constants where possible to reduce risks.

## Known Limitations

- Weekdays frequency not fully implemented (simplified to daily); extend with weekday calculation logic.
- Multiple consecutive misses handled with simplified calculation; may not perfectly account for grace edges.
- Assumes Chainlink price feed is reliable; add fallback or multi-oracle in production.
- No withdrawal of full stake implemented (add if needed for end of duration).
- Privacy via commitment hash; no verification proof for private habits.

## Audit Recommendations

- Recommend full audit by a professional firm (e.g., OpenZeppelin, Trail of Bits) before mainnet deployment.
- Focus on reward distribution math, penalty calculations, and cross-contract interactions.
- Run static analysis (Slither, Mythril) and invariant testing.
