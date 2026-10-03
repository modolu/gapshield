# GapShield — Submission Form Copy

Copy-ready text for the HackQuest / Arbitrum Open House form. Every claim here is backed by the repository and
[`TESTNET_DEMO_EVIDENCE.md`](TESTNET_DEMO_EVIDENCE.md). Please keep the oracle disclaimer whenever you shorten anything.

## Project name
GapShield

## Tagline
Protect the gap. Keep the exposure.

## One-line description
Fixed-price, fully collateralized weekend gap protection for tokenized stocks, paid in USDG on Robinhood Chain.

## 50-word description
GapShield protects tokenized-stock holders from weekend gaps. Before Friday's cutoff, a holder pays a fixed USDG
premium. If Monday's open is more than 5% below Friday's close, the contract pays the excess, capped at 5%, from a fully
collateralized USDG pool. Live on Robinhood Chain Testnet with a demo oracle.

## 100-word description
Tokenized US stocks trade on-chain around the clock, but their reference market closes every weekend. Weekend news
becomes a Monday gap that stop-losses can't fill through. GapShield sells one simple protection: pay a fixed USDG premium
before Friday's cutoff, and if Monday opens more than 5% below Friday's close, receive the excess, capped at 5%. Premiums
are escrowed and each policy's worst-case payout is reserved at purchase, so the pool is always fully collateralized.
Underwriters earn 88% of premiums. A full lifecycle, including a 40 USDG payout, ran live on Robinhood Chain Testnet using
an explicitly labeled testnet demo oracle.

## 200-word description
Tokenized US equities trade on-chain at any hour, but the underlying market closes from Friday 4:00 PM
ET until the next regular session. When news breaks over the weekend, Monday can open far below Friday's close, and
stop-losses cannot fill through that gap. The alternatives are blunt: hold and hope, sell on Friday and
lose the upside, trade thin weekend liquidity, or learn an options interface for a single recurring risk.

GapShield packages that risk into one decision. Before Friday's cutoff, a holder chooses a whole-USDG amount and pays a
fixed premium (0.80%). If the stock opens Monday more than 5% below Friday's close, the contract pays the excess, capped
at 5% of the amount covered. Underwriters deposit USDG into an ERC-4626 pool that reserves every policy's worst-case
payout at purchase and earns 88% of premiums.

Settlement is deterministic from two reference prices recorded through a pluggable oracle interface. If no valid
settlement arrives by the deadline, anyone can void the epoch and buyers are fully refunded. GapShield is deployed on
Robinhood Chain Testnet with Paxos USDG. A full lifecycle, including a 40 USDG payout on a 9% gap, is recorded on-chain.
Testnet settlement uses a trusted demo oracle.

## Problem
Tokenized stocks trade 24/7, but their reference market doesn't. From Friday close to the next regular open, news keeps
arriving while the market that sets the price is shut. The Monday open can gap sharply, and a stop-loss can't fill
through a gap. Holders have no simple way to keep their position over the weekend while capping that specific
downside. Options can do it, but they demand strike and expiry choices, approvals, and far more complexity than one
recurring event needs.

## Solution
GapShield is a single-purpose, fixed-price protection contract. The buyer knows the premium and maximum payout before
signing, with one sentence of terms: "pays the gap beyond 5%, capped at 5%." Underwriters see their maximum liability
before depositing. Payouts are computed deterministically from Friday's close and Monday's open references and claimed
on-chain. There are no claim forms or adjusters, and no margin or liquidation.

## How it works
1. Underwriters deposit USDG into the ERC-4626 `ProtectionPool`.
2. The operator opens a weekly epoch with explicit UTC times for the sale cutoff, close window, open window and
   settlement deadline.
3. A buyer purchases a whole-USDG notional before the cutoff. The premium is escrowed, the worst-case payout (5% of
   notional) is reserved, and a non-transferable receipt is minted.
4. The operator records the close and open references through the epoch's oracle adapter. The pool validates the feed,
   the time window and the price, and rejects future-dated references.
5. Settlement computes the gap, moves owed payouts into a claimable bucket, releases the reserve, and splits the premium
   88% to LPs and 12% to the protocol.
6. The receipt owner claims. If settlement never arrives, anyone can void the epoch after the deadline and buyers
   reclaim their full premium.

## Technical implementation
- Solidity 0.8.37 with Foundry and OpenZeppelin 5.7. No upgradeable proxies.
- `ProtectionPool`: ERC-4626 vault and settlement state machine. Its LP accounting is tracked internally, not from the
  token balance. Premium escrow, settled claimable payouts and protocol fees are separate buckets that never count as
  LP capital.
- `ProtectionReceipt`: non-transferable ERC-721 receipt (ERC-5192 `locked`).
- `PremiumMath`/`PayoutMath`: pure integer math. Premium rounds up and payouts round down. Whole-USDG notionals make the
  aggregate payout equal the sum of individual payouts exactly.
- `IReferenceOracle`: stateless adapter interface. `SnapshotOracle` is the testnet demo adapter. A Pyth Pro adapter with
  per-feed `feedUpdateTimestamp` and `marketSession` checks fits without changing storage.
- Epoch states: Open → CloseRecorded → Settled, or → Voided at or after the deadline. Settlement and void windows never
  overlap.
- Foundry scripts for deployment, demo epochs and an idempotent live-demo driver.

## Why this matters
Tokenized equities are growing, and every holder faces the same weekend closure every week. GapShield turns an
unmanaged, discontinuous risk into a known, prepaid cost, without asking holders to sell or to become options traders.
It is the kind of narrow risk primitive that wallets, tokenized-stock venues and lending markets could embed directly.

## Why Robinhood Chain / Arbitrum
Robinhood Chain is an Arbitrum chain built for financial products and tokenized equities, the exact asset class
GapShield protects. Standard Solidity and Foundry deployed without modification. Paxos USDG and Pyth Pro are both
present on Robinhood Chain and Arbitrum, so the stablecoin and the planned production oracle path are native to the
ecosystem.

## Business model
GapShield keeps 12% of each premium as a protocol fee, and underwriters receive 88%. Revenue scales with covered notional
and protected weekends. Longer term, the plan is embedded distribution: B2B integrations, volume fees and risk data.
These are hypotheses, not demonstrated revenue.

## Target users
- **Primary:** non-US holders of tokenized US stocks who keep positions over weekends and want bounded downside without
  options.
- **Secondary:** USDG holders who want premium income for explicit, capped risk.
- **Later:** lending markets, vaults and venues buying protection in bulk.

## Market opportunity
CoinGecko reported roughly $487M in spot tokenized-stock market value at the end of Q1 2026. The category is early. We
size the opportunity by protected notional (notional × protected weekends × premium × fee share) rather than by
headline options volume, and make no market-share claims.

## Competitive differentiation
Adjacent projects validate the risk category but solve different problems:
- Gapguard protects LPs through dynamic fees;
- LATCH offers analytics only;
- Denar freezes lending actions;
- Plume and generic on-chain options markets require strike and expiry decisions.

GapShield pays the holder directly for the close-to-open gap, with a fixed price, a known maximum payout, full
collateralization and deterministic settlement.

## Current traction / validation
- Deployed on Robinhood Chain Testnet. A full lifecycle was executed live: an epoch voided after an oracle-failure
  timeout, then a policy bought, settled on a 9% gap and claimed for 40 USDG, with accounting reconciled exactly
  on-chain.
- 208 automated tests, including a stateful invariant suite (15 properties over 256 randomized sequences of 128 calls, 32,768 calls total)
  and 10,000-run fuzzing in CI.
- No external users or underwriters yet. Testnet only, unaudited.

## What was built during the hackathon
The hackathon build delivered:
- the product brief and architecture;
- the protection pool, receipt, math libraries, oracle interface and testnet demo oracle;
- the full test suite, including the fuzz and invariant suites;
- CI;
- the deployment, demo-epoch and live-demo scripts;
- the Robinhood Chain Testnet deployment and the recorded on-chain demo.

The web app is a scaffold only.

## Demo instructions
1. Read the README, then open `docs/TESTNET_DEMO_EVIDENCE.md` for every transaction hash.
2. Open the Robinhood Testnet explorer links for the purchase, `settleOpen` and `claim` transactions.
3. Check live state, for example
   `cast call 0xA1De944d3d1247747a020AB7C325431D9221B13d "totalAssets()(uint256)" --rpc-url https://rpc.testnet.chain.robinhood.com`,
   which returns `967040000` (967.04 USDG).
4. Locally: `git clone --recursive https://github.com/modolu/gapshield.git`, then `forge test`. Run
   `forge test --match-contract LifecycleTest -vv` for the calm, triggered, capped, void and multi-policy scenarios.
5. To replay on testnet: `script/RunTestnetDemo.s.sol` (see `docs/DEPLOYMENT.md`).

## GitHub URL
https://github.com/modolu/gapshield

## Deployed contract addresses (Robinhood Chain Testnet, chain ID 46630)
- ProtectionPool: `0xA1De944d3d1247747a020AB7C325431D9221B13d`
- ProtectionReceipt: `0x19573Ed5eee1D348626679737844E769527C1c46`
- SnapshotOracle (TESTNET DEMO ORACLE): `0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6`
- USDG (official Paxos): `0x7E955252E15c84f5768B83c41a71F9eba181802F`

## Testing summary
- 208 Foundry tests: 181 unit, 6 lifecycle integration, 3 deploy-script, 17 fuzz (1,000 runs locally, 10,000 in CI) and
  a stateful invariant suite.
- The invariant suite drives the full lifecycle: epochs, LP flows, purchases, settlement, void, claims, refunds, fees,
  pause and donations. It checks 15 properties over 256 × 128 calls, including solvency, exact bucket accounting, no
  double claims, frozen settled references, and pause never trapping funds.
- CI runs on GitHub Actions and is green.

## Oracle disclaimer
Testnet settlement uses `SnapshotOracle`, a TESTNET DEMO ORACLE. A single trusted operator posts the reference prices,
and the contract identifies itself on-chain as "TESTNET DEMO ORACLE". It is not decentralized, not a market data
source, and not safe for production or real funds. A Pyth Pro adapter is designed but not yet built.

## Roadmap
1. Pyth Pro adapter (per-feed freshness and regular-session checks), then permissionless settlement.
2. Mobile buyer and underwriter app.
3. More equities and tiers, calibrated pricing, holiday and earnings events.
4. Audit, multisig and timelock governance, and a legal distribution path before any mainnet launch.
5. B2B embedding in wallets, venues and lending markets.
