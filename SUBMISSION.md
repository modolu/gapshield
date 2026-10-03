# GapShield — Arbitrum Open House Singapore Submission

**Protect the gap. Keep the exposure.**

GitHub: https://github.com/modolu/gapshield · Live proof: [`docs/TESTNET_DEMO_EVIDENCE.md`](docs/TESTNET_DEMO_EVIDENCE.md) ·
Network: Robinhood Chain Testnet (46630) · Asset: Paxos USDG

## Overview

GapShield sells fixed-price, fully collateralized protection against one specific risk: a tokenized stock opening
Monday far below Friday's close. A holder pays a known USDG premium before Friday's cutoff. If the Monday open is more
than 5% below Friday's close, the contract pays the excess, capped at 5% of notional, from a USDG underwriting pool.
There are no Greeks, no margin and no claim forms. The full lifecycle runs on Robinhood Chain Testnet today.

## Problem

Tokenized US stocks are on-chain around the clock, but the underlying market closes from Friday 4:00 PM ET until the next
session. Weekend news turns into a Monday gap, and stop-losses can't fill through it. Holders can hope, sell on Friday
and give up the upside, trade thin weekend liquidity, or learn a full options interface for one recurring event.

## Solution

One event, one price, one decision: "pays the gap beyond 5%, capped at 5%." The buyer knows the premium and maximum
payout before signing. Underwriters know their maximum liability before depositing. Settlement is deterministic from
two reference prices, and the receipt owner claims on-chain.

## Why tokenized equities need this

The token can trade on Saturday, but the reference market can't. That mismatch is structural and repeats every weekend
and holiday. Adjacent projects address it from other sides: LP fee protection, risk analytics, lending freezes and
general options. GapShield protects the **holder's** close-to-open downside directly, as a simple add-on.

## How it works

1. LPs deposit USDG into an ERC-4626 pool.
2. The owner opens a weekly epoch with explicit UTC times for the sale cutoff, close window, open window and settlement
   deadline. There's no on-chain market calendar.
3. A buyer purchases a whole-USDG notional before the cutoff. The pool escrows the premium, reserves the worst-case
   payout, and mints a non-transferable receipt.
4. The operator records the close and open references through the epoch's oracle adapter. The pool re-checks the
   window, rejects future-dated references and requires a positive price.
5. Settlement moves owed payouts out of LP assets into a claimable bucket, releases the reserve, and splits the premium
   88% to LPs and 12% to the protocol.
6. The buyer claims. With no settlement by the deadline, anyone can void the epoch and buyers get a full premium refund.

## Technical architecture

- Solidity 0.8.37, Foundry, OpenZeppelin 5.7. No proxies, no loops over policies or LPs.
- `ProtectionPool` (ERC-4626 vault and settlement state machine), `ProtectionReceipt` (non-transferable ERC-721,
  ERC-5192 `locked`), `PremiumMath`/`PayoutMath` (pure integer math).
- `IReferenceOracle` is a stateless adapter interface. `SnapshotOracle` is the testnet adapter. A Pyth Pro adapter
  (per-feed `feedUpdateTimestamp` and `marketSession`) can be added without changing pool storage.
- Epoch states: Open → CloseRecorded → Settled, or Open/CloseRecorded → Voided at or after the deadline.

## Why Robinhood Chain and the Arbitrum ecosystem

Robinhood Chain is an Arbitrum chain built for financial products and tokenized equities, which is exactly the asset
class GapShield protects. Standard Solidity tooling deployed unchanged. USDG and Pyth Pro are both present on Robinhood
Chain and Arbitrum, and the contracts are chain-agnostic within the Arbitrum ecosystem.

## USDG integration

USDG is the only asset in the system: LP collateral, premiums, payouts, refunds and protocol fees. The deployment uses
the official Paxos Robinhood Testnet USDG (`0x7E955252E15c84f5768B83c41a71F9eba181802F`). The deploy script checks it
has code, 6 decimals and the USDG symbol, and refuses to deploy otherwise.

## Demo oracle disclaimer

Testnet settlement uses **`SnapshotOracle`, a TESTNET DEMO ORACLE**. A single trusted operator posts the prices, and the
contract reports `ORACLE_KIND() == "TESTNET DEMO ORACLE"` on-chain. It is not production-safe, not decentralized, and
not a market data source.

## Live deployed contracts (Robinhood Chain Testnet, 46630)

| Contract | Address |
|---|---|
| ProtectionPool | `0xA1De944d3d1247747a020AB7C325431D9221B13d` |
| ProtectionReceipt | `0x19573Ed5eee1D348626679737844E769527C1c46` |
| SnapshotOracle (TESTNET DEMO ORACLE) | `0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6` |
| USDG (official Paxos) | `0x7E955252E15c84f5768B83c41a71F9eba181802F` |

## Live demo proof

All transactions are listed, with block numbers, in [`docs/TESTNET_DEMO_EVIDENCE.md`](docs/TESTNET_DEMO_EVIDENCE.md).

- **Epoch 1, void path:** no settlement arrived, so after its deadline `voidEpoch(1)` moved it to `Voided`.
- **Epoch 2, policy 1:**
  - bought 1,000 USDG of cover for an 8 USDG premium;
  - settled with close 100.00 and open 91.00, a 9% gap of which 4% was covered;
  - **claimed 40 USDG**.
- **Final pool state:** LP assets 967.04 USDG, protocol fees 0.96 USDG, claimable payouts 0, reserve 0, escrow 0.
  The pool balance (968 USDG) reconciles exactly.

## Core economics (prototype tier)

| Term | Value |
|---|---|
| Trigger | 5% |
| Max cover | 5% |
| Premium | 0.80% of notional |
| Split | 88% LP / 12% protocol |
| Notional per policy | 10 – 10,000 USDG |
| Utilization cap | 50% |
| Example | 1,000 USDG: premium 8, max payout 50 |

These are illustrative prototype parameters, not actuarial pricing.

## Key differentiators

- Protects the holder, not LPs or lenders. It's a single-purpose product, not an options market.
- Known premium and known maximum payout. Settlement is deterministic and claims are on-chain.
- Fully collateralized, with explicit, separate accounting buckets an underwriter can inspect.
- Oracle-agnostic interface with a deterministic, permissionless fallback when the oracle fails.

## Security and solvency model

- Worst-case liability is reserved at purchase, and capacity counts LP-owned assets only.
- Escrowed premium, settled claimable payouts and protocol fees are never LP capital or free collateral.
- Settlement and void windows are disjoint, and there's no admin void.
- Pause blocks new risk only. It never blocks settlement, claims, refunds or free withdrawals.
- **Testing:** 208 Foundry tests, run with 10,000 fuzz runs in CI. They include a stateful invariant suite that checks
  15 properties over 256 randomized sequences of 128 calls (32,768 calls total).
- **Unaudited.**

## Current limitations

- Trusted demo oracle; operator-gated settlement.
- One asset (TSLA), one tier, one active epoch.
- Fixed prototype pricing.
- No frontend yet.
- Contracts not source-verified on Blockscout: the explorer lacks solc 0.8.37. The bytecode match is documented
  instead.
- Testnet only. No users beyond the team.

## Roadmap

1. Pyth Pro adapter with per-feed freshness and market-session checks, then permissionless settlement.
2. Mobile buyer and underwriter app (quote, payout scrubber, solvency bar, claim).
3. Multiple equities and tiers, historically calibrated pricing, holiday and earnings events.
4. Audit, multisig and timelock administration, and a compliant distribution path before any mainnet use.
5. Embedded B2B distribution through wallets, tokenized-stock venues and lending markets.
