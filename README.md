# Are You The Wombat

A game written in Zig where you match up wombats in their winter burrow.

## Game Logic

The game has the same underlying logic as reality TV show "Are You The One", but it's about wombats.

### Modes

**Standard mode** = M males and M females giving N=2M total contestants and M! possibile scenarios.

**Bisexual mode** = N total contestants, each of which can be paired with any other contestant other than themselves, giving (N-1)!! = N!/(2^(N/2) * (N/2)!) possible scenarios. (x!! means the double factorial of x, which is like a factorial but you skip every other number, e.g. 5! = 5 * 3 * 1).

The following tables show the total n# scenarios for each n# contestants, which puts constraints on the solvability of the setup.

**Standard mode**

| N | Num possibilities |
| - | ----------------- |
| 2 | 1 |
| 4 | 2 |
| 6 | 6 |
| 8 | 24 |
| 10 | 120 |
| 12 | 720 |
| 14 | 5,040 |
| 16 | 40,320 |
| 18 | 362,880 |
| 20 | 3,628,800 |
| 22 | 39,916,800 |
| 24 | 479,001,600 |
| 26 | 6,227,020,800 |
| 28 | 87,178,291,200 |
| 30 | 1,307,674,368,000 |

**Bisexual mode**

| N | Num possibilities |
| - | ----------------- |
| 2 | 1 |
| 4 | 3 |
| 6 | 15 |
| 8 | 105 |
| 10 | 945 |
| 12 | 10,395 |
| 14 | 135,135 |
| 16 | 2,027,025 |
| 18 | 34,459,425 |
| 20 | 654,729,075 |
| 22 | 13,749,310,575 |
| 24 | 316,234,143,225 |
| 26 | 7,905,853,580,625 |
| 28 | 213,458,046,676,875 |
| 30 | 6,190,283,353,629,375 |

## Status

| Feature | Status |
| ------- | ------ |
| Implement underlying logic and probability calculations for standard mode. | ☑️ Done |
| Implement underlying logic and probability calculations for bisexual mode. | ☑️ Done |
| Implement UI scaffolding | □ Todo |
| Implement UI for main menu | □ Todo |
| Implement UI for starting game | □ Todo |
| Implement UI for playing through game | □ Todo |
| Implement UI for endgame success/fail | □ Todo |
| Implement UI for sharing game results (QR code?) | □ Todo |
