# GapShield

**Protect the gap. Keep the exposure.**

GapShield is fixed-price, fully collateralized weekend gap protection for tokenized US stocks, paid in Paxos USDG and
built for Robinhood Chain. A holder buys protection before Friday's cutoff. If the stock opens Monday more than 5%
below Friday's close, the contract pays the excess, capped at a further 5%, from an underwriting pool. No options, no
margin, no claim forms.

> **Status: testnet prototype.** Deployed on Robinhood Chain Testnet, with a full live lifecycle recorded in
> [`docs/TESTNET_DEMO_EVIDENCE.md`](docs/TESTNET_DEMO_EVIDENCE.md). Settlement currently uses **`SnapshotOracle`, a
> TESTNET DEMO ORACLE**: a trusted operator posts the reference prices. It is **not production-safe** and must never
> back real money. There is no frontend yet; the demo runs through Foundry scripts and the block explorer.

## The problem

Tokenized stocks trade on-chain around the clock, but the underlying US market closes from Friday 4:00 PM ET until the
next regular session. News that breaks over the weekend can make a stock open far below Friday's close, and a stop-loss
can't guarantee a price through that gap. Today holders either hope, sell on Friday and give up the upside, trade thin
weekend liquidity, or learn a full options interface for one recurring risk.

## How it works

1. **Underwriters** deposit USDG into an ERC-4626 pool and earn 88% of premiums for bounded, visible risk.
2. **Buyers** choose a whole-USDG notional before the sale cutoff and pay a fixed premium (0.80%). The pool reserves the
   policy's worst-case payout (5% of notional) in the same transaction, and the buyer receives a non-transferable
   receipt.
3. **Settlement:** the settlement operator records the Friday close and Monday open references through the epoch's
   oracle adapter. The pool checks the feed, the time windows (and rejects future-dated references) and a positive
   price, then settles in one step:
   `gap = (close − open) / close`, `covered = min(max(gap − 5%, 0), 5%)`, `payout = notional × covered`.
4. **Claim:** the receipt owner calls `claim` and is paid in USDG. If no valid settlement arrives by the deadline,
   anyone can void the epoch and every buyer gets a full premium refund.

**Example (live on testnet):** 1,000 USDG covered, close 100.00 → open 91.00. The gap is 9%, covered 4%, payout
**40 USDG**. Premium 8 USDG: 0.96 to the protocol, 7.04 to LPs.

## Safety model

- **Fully collateralized.** Worst-case payout is reserved at purchase, with a 50% utilization cap and a per-epoch
  liability cap.
- **Separate accounting buckets.** LP assets, escrowed premium, settled-but-unclaimed payouts and protocol fees are
  tracked separately. Escrowed premium and owed payouts never count as LP capital or selling capacity.
- **Hard sale cutoff.** One active epoch at a time, and epoch terms are immutable once created.
- **Deterministic fallback.** Settlement and void windows are disjoint (`< deadline` vs `>= deadline`). There is no
  admin void, and pause never blocks settlement, claims, refunds or free-collateral withdrawal.
- **Exact math.** Integer math only. Payouts round down and premium rounds up. Whole-USDG notionals make the aggregate
  payout equal the sum of individual payouts exactly.

## Live deployment — Robinhood Chain Testnet (chain ID 46630)

| Contract | Address |
|---|---|
| ProtectionPool | [`0xA1De944d3d1247747a020AB7C325431D9221B13d`](https://explorer.testnet.chain.robinhood.com/address/0xA1De944d3d1247747a020AB7C325431D9221B13d) |
| ProtectionReceipt | [`0x19573Ed5eee1D348626679737844E769527C1c46`](https://explorer.testnet.chain.robinhood.com/address/0x19573Ed5eee1D348626679737844E769527C1c46) |
| SnapshotOracle (TESTNET DEMO ORACLE) | [`0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6`](https://explorer.testnet.chain.robinhood.com/address/0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6) |
| USDG (official Paxos) | [`0x7E955252E15c84f5768B83c41a71F9eba181802F`](https://explorer.testnet.chain.robinhood.com/address/0x7E955252E15c84f5768B83c41a71F9eba181802F) |

The addresses are also in [`deployments/46630.json`](deployments/46630.json). Every transaction of the live demo is in
[`docs/TESTNET_DEMO_EVIDENCE.md`](docs/TESTNET_DEMO_EVIDENCE.md).

The contracts are not source-verified on Blockscout, because the explorer doesn't support solc 0.8.37 yet. The
evidence file shows how to confirm the deployed bytecode matches this repository.

## Repository

| Path | Contents |
|---|---|
| `contracts/` | `ProtectionPool`, `ProtectionReceipt`, `oracles/SnapshotOracle`, `PremiumMath`/`PayoutMath`, `IReferenceOracle`, `mocks/MockUSDG` (local only) |
| `test/` | Unit, integration, fuzz and stateful invariant tests (Foundry) |
| `script/` | `DeployGapShield`, `CreateDemoEpoch`, `RunTestnetDemo` |
| `docs/` | Deployment runbook, testnet demo evidence, Phase 0 decisions |
| `GAPSHIELD_PRODUCT_BRIEF.md`, `GAPSHIELD_PRODUCT_ARCHITECTURE.md` | Product and technical source of truth |
| `web/` | Next.js scaffold (no product UI yet) |

## Build and test

Requires [Foundry](https://getfoundry.sh) and Node 22+.

```sh
git clone --recursive https://github.com/modolu/gapshield.git && cd gapshield
forge build
forge test                 # 208 tests: unit, integration, fuzz, invariants
FOUNDRY_PROFILE=ci forge test   # 10,000 fuzz runs, as in CI
```

The invariant suite drives the full lifecycle: epochs, LP flows, purchases, settlement, void, claims, refunds, fees,
pause and donations. It checks 15 solvency and accounting properties after every call.

## Run the demo

- **Local:** `forge test --match-contract LifecycleTest -vv` runs the calm, triggered, capped, oracle-failure and
  multi-policy scenarios.
- **Testnet:** deployment, verification and the demo flow are in [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).
  `script/RunTestnetDemo.s.sol` replays the full lifecycle against deployed contracts. Re-running it is safe; it never
  repeats a transaction.

## Limitations

- `SnapshotOracle` is trusted and operator-posted. A Pyth Pro adapter (per-feed `feedUpdateTimestamp` and
  `marketSession` checks) is designed for but not built, pending data access.
- Settlement is operator-gated. There is one asset (TSLA), one tier and one active epoch.
- Premium is a fixed prototype rate, not actuarially priced.
- The contracts are unaudited, there is no frontend yet, and it's testnet only.

## License

MIT — see [`LICENSE`](LICENSE).
