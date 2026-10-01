# GapShield — Phase 0 Decisions

Status: **FROZEN for Phase 1** · Verified 2026-10-01 · Deltas P1–P6 approved by owner 2026-10-01 · P7 approved 2026-10-01 for Phase 2 · Scope: decision freeze only (no protocol code)

Source of truth: `GAPSHIELD_PRODUCT_BRIEF.md` (624 lines) and `GAPSHIELD_PRODUCT_ARCHITECTURE.md` (1,351 lines). This document records externally verified facts, decisions made within the architecture's existing scope, and the owner-approved architecture deltas (§9) that govern Phase 1 where the architecture is silent.

Evidence labels: **[on-chain]** = read directly from Robinhood Chain Testnet via JSON-RPC on 2026-10-01; **[docs]** = current official documentation fetched 2026-10-01; **[api]** = live response from a public API.

---

## 1. Competition (HackQuest)

Source: https://www.hackquest.io/hackathons/Arbitrum-Open-House-Singapore-Online-Buildathon [docs]

| Item | Verified value |
|---|---|
| Submission window | `Sep 13,2026 17:01 - Oct 4,2026 15:59` |
| Registration window | `Jul 29,2026 17:01 - Oct 2,2026 17:01` (page showed "1 days left") |
| Reward announcement | `Oct 12,2026 06:00` |
| **Timezone** | **Not shown on the page. Not verified.** Assume the earliest plausible reading and submit early. |
| Deployment qualification | "Your project must be deployed on an Arbitrum chain to qualify." Examples given: Arbitrum Sepolia, Arbitrum One, Robinhood Chain. Testnet qualifies. |
| Judging criteria | Smart contract quality; Product-Market Fit; Innovation and Creativity; Real Problem Solving |
| USDG | "Extra consideration is given to projects integrating Paxos' USDG stablecoin." |
| Robinhood reservation | "At minimum, 1 of 3 prizes is reserved for a project building on Robinhood Chain" (also 1 of 3 reserved for Arbitrum). Stated under both Overall and Promising Products. |
| Prizes (115,000 USD total) | Overall 70,000 USDC (40k / 20k / 10k); Promising Products 15,000 USDC (7k / 5k / 3k); Grants up to 30,000 USDC, milestone-based, discretionary |
| Prize conditions | "All prizes are subject to development-tied milestones." See Terms & Conditions. |
| Required submission artifacts | **Not listed on the page.** The only stated requirement is the on-chain deployment. |

Not verified: the Terms & Conditions PDF (`https://openhouse.arbitrum.io/singapore_version_open_house_buildathon_terms___conditions.pdf`) returned HTTP 429. It may define the timezone and the submission requirements. **User action: read it manually.**

**User action (time-critical): confirm HackQuest registration before `Oct 2,2026 17:01` (timezone unverified).**

## 2. Network — Robinhood Chain Testnet

Sources: https://docs.robinhood.com/chain/connecting [docs], RPC [on-chain]

| Item | Value | Evidence |
|---|---|---|
| Chain ID | `46630` | [docs]; `eth_chainId` → `0xb626` [on-chain] |
| Gas token | ETH | [docs] |
| Public RPC | `https://rpc.testnet.chain.robinhood.com` | [docs]; responsive, block 127,062,863 [on-chain] |
| Explorer | `https://explorer.testnet.chain.robinhood.com` (Blockscout; `/api/v2` responds) | [docs], [api] |
| Faucet | `https://faucet.testnet.chain.robinhood.com` (linked from HackQuest resources; returned 429 to an automated fetch) | [docs] |
| Rate limits | Public endpoints "are rate-limited and not recommended for production use"; no figures published | [docs] |
| Free fallback | Alchemy (`https://robinhood-testnet.g.alchemy.com/v2/{API_KEY}`, documented as the recommended provider) or dRPC (`https://drpc.org/chainlist/robinhood-testnet-rpc`) | [docs] |
| Stack | "an Arbitrum Layer-2 Chain built on Ethereum, using Ethereum blobs for data availability" | [docs] |

Compiler target: `evm_version = cancun` (conservative; Arbitrum supports Cancun opcodes).

## 3. USDG

Source: https://docs.paxos.com/guides/stablecoin/usdg/testnet [docs]

| Network | Address | Evidence |
|---|---|---|
| **Robinhood Testnet (primary)** | `0x7E955252E15c84f5768B83c41a71F9eba181802F` | Listed by Paxos [docs]. On-chain: proxy (EIP-1967 impl `0xf0863d7a29a55d0c4263c11bfac754312ff078df`), `name()` = "Global Dollar", `symbol()` = "USDG", **`decimals()` = 6**, `paused()` = false [on-chain] |
| Arbitrum Sepolia (optional mirror) | `0xFFC95faa3d63Cde504a05B567C600B78C0b41892` | Listed by Paxos [docs]; not checked on-chain |

- Paxos docs do not state decimals. **6 is verified on-chain.**
- USDG is an upgradeable, pausable Paxos proxy. Phase 1 must treat it as an external ERC-20 that may pause or revert, and must use `SafeERC20`.
- Testnet USDG source: `https://faucet.paxos.com/` (linked from Paxos docs; returned 403 to an automated fetch). **User action: confirm faucet access and the amount per request.**

## 4. Oracle

### 4.1 Verifier contract
`0xACeA761c27A909d4D3895128EBe6370FDE2dF481` is listed for Robinhood Chain Testnet at https://docs.pyth.network/price-feeds/pro/contract-addresses [docs]. The same address is listed for Robinhood mainnet, Arbitrum One and Arbitrum Sepolia. On-chain [on-chain]:
- deployed proxy (impl `0xd8f4a467abec64bc944eee1325b9007879b6555b`);
- **`verification_fee()` = 1 wei**;
- owner `0x0708325268dF9F66270F1401206434524814508b`.

### 4.2 Four separate states (deliberately not merged)

| State | Status | Evidence |
|---|---|---|
| Verifier deployed on Robinhood Testnet | **PASS** | §4.1 |
| Desired equity feed exists | **PASS** | Public catalog `GET https://pyth.dourolabs.app/v1/symbols?query=TSLA&asset_type=equity` (no auth) → `Equity.US.TSLA/USD`, `pyth_lazer_id` **1435**, `state: stable`, `exponent: -5`, `min_channel: fixed_rate@50ms` [api] |
| Our token is entitled to the feed | **BLOCKED** | No Pyth credential exists in this environment. `POST https://pyth-lazer.dourolabs.app/v1/latest_price` without auth → HTTP 403 [api]. Tokens are permissioned by asset type, minimum channel and optional feed IDs (Pyth FAQ). |
| Signed EVM payload usable on-chain | **DEFERRED** | Can't be tested without entitlement. Library support is confirmed (§4.3). |

### 4.3 Freshness and session — requirement for the future Pyth adapter
Pyth Pro payload reference [docs]:
- "once a feed produces its first valid price, a price will always be provided for that feed going forward — even during off-hours (the most recent price will be carried forward)."
- "If `feedUpdateTimestamp` is earlier than `timestampUs`, the price is the most recent available price, carried forward."
- "Consumers should always rely on `feedUpdateTimestamp` to understand the freshness and origin of the price."
- `marketSession` (per feed) takes the values `regular`, `preMarket`, `postMarket`, `overNight`, `closed`.

On-chain parsing is supported by `pyth-crosschain/lazer/contracts/evm`:
- `PriceFeedProperty.FeedUpdateTimestamp` (uint64, µs) and `PriceFeedProperty.MarketSession` (enum `Regular=0, PreMarket, PostMarket, OverNight, Closed`);
- getters `getFeedUpdateTimestamp` and `getMarketSession`;
- `PythLazer.verifyUpdate` is `payable` and requires `msg.value >= verification_fee`.

**Requirement for the Phase 2 adapter.** This follows from the architecture's existing "feed ID + publish-time window" control. The adapter MUST request `price`, `exponent`, `feedUpdateTimestamp` and `marketSession`, and MUST verify, per feed:
1. the feed ID equals the epoch's feed ID;
2. `marketSession == Regular`;
3. `feedUpdateTimestamp` lies inside the configured window. The payload-level timestamp alone is NOT sufficient;
4. `exponent` equals the asset's configured exponent (−5);
5. `price > 0`;
6. the signature passes `verifyUpdate`, with the fee forwarded.

### 4.4 Settlement path decision

- **`SnapshotOracle` = hackathon settlement path.** Labeled TESTNET DEMO everywhere it appears.
- **`PythReferenceOracle` = preferred production-like integration.** Phase 2, only if entitlement is obtained.

User action to unblock Pyth (optional, non-blocking):
1. Create a free Pyth Terminal account (https://docs.pyth.network/price-feeds/pro/acquire-api-key). Put the key in a local `.env` as `PYTH_PRO_API_KEY` and never commit it.
2. Entitlement probe: `GET https://pyth.dourolabs.app/v1/symbols?entitled_only=true` with `Authorization: Bearer …`. Feed 1435 must be listed.
3. Payload probe:
   - `POST https://pyth-lazer.dourolabs.app/v1/latest_price` with `priceFeedIds:[1435]`, `properties:["price","exponent","feedUpdateTimestamp","marketSession"]`, `formats:["evm"]`;
   - then call `verifyUpdate` on the testnet verifier with 1 wei.
4. Historical references: `POST /v1/price` takes a `timestamp` in µs. The docs show `formats:["solana"]`; whether `evm` works for past timestamps is **unverified**.

## 5. ZeroDev

https://docs.zerodev.app/sdk/faqs/chains lists `Robinhood | 4663` and `Robinhood Testnet | 46630` [docs]. The table has no bundler or paymaster columns.

- Network support: **listed (verified).**
- Bundler, paymaster and sponsorship for our project: **not verified; needs a smoke test.**
- Status: **non-critical.** There is no ZeroDev SDK in the repo. EOA/injected wallet is the launch path, per architecture §3 and §18.

## 6. MVP asset — TSLA

| Criterion | TSLA (`1435`) | AAPL (`922`) |
|---|---|---|
| Pyth Pro feed exists, `stable` | yes | yes |
| Exponent | −5 | −5 |
| Regular-session schedule (NYSE holidays and early closes encoded) | identical | identical |
| Overall `min_publishers` | 2 | 1 |
| Regular-session `min_pub` | 3 | 3 |
| Entitlement | unknown (no key) | unknown (no key) |
| Historical data | same API for both | same API for both |
| Demo salience (weekend gap risk) | high | lower |

**Decision: TSLA.**
- On oracle evidence the two are tied, except that TSLA has the higher `min_publishers` (2 vs 1).
- Entitlement can't be checked for either asset yet, so it doesn't distinguish them.
- TSLA also matches the product brief and has the stronger weekend-gap story.

Asset config: `symbol = "TSLA"`, `oracleFeedId = bytes32(uint256(1435))`, price exponent −5 (`priceDecimals = 5`).

## 7. Economics (single MVP tier — hackathon prototype parameters, not actuarial pricing)

| Parameter | Value | Note |
|---|---|---|
| `triggerBps` | **500** | 5.00% downside gap |
| `maxCoverBps` | **500** | pays for the part of the gap between 5% and 10% |
| `premiumBps` | **80** | 0.80% of notional |
| `utilizationCapBps` | **5000** | reserved liability ≤ 50% of pool collateral |
| Protocol fee | **1200 bps of premium** | 88% underwriting / 12% protocol (Brief §11) |
| `minNotional` | **10 USDG** (`10_000_000`) | Tiny-policy spam control (Architecture §11). Premium on 10 USDG is 0.08 USDG. |
| Notional granularity | **whole USDG**: `notional % 1_000_000 == 0`; `minNotional` and `maxNotional` must also be whole USDG | With 6 decimals, payout = `k × 100 × coveredBps` exactly, so the aggregate `owed` equals the sum of the individual rounded-down payouts. No dust and no loops (approved by owner). |
| `maxNotional` (per policy) | **10,000 USDG** (`10_000_000_000`) | Stops one buyer using up all demo capacity. Architecture §16 already tests "min/max notional". |
| `maxAggregateLiability` | per-epoch config (existing field); demo default **2,500 USDG** | The utilization cap still applies on top. |

Rounding (approved, P6):
- `gapBps`, `coveredBps`, `maxPayout`, `payout` and the protocol fee **round down**.
- **Premium rounds up** (`Math.mulDiv(..., Rounding.Ceil)`). This favors the pool by at most 1 micro-USDG.

Worked example (Architecture §8): 1,000 USDG notional → premium 8.00, max payout 50.00. Friday 100 → Monday 91 → payout 40.00.

## 8. Epoch semantics (explicit UTC timestamps; no on-chain calendar)

Reference meaning:
- **Close:** a Pyth regular-session price (`marketSession == Regular`) whose `feedUpdateTimestamp` falls in the last minute before the scheduled regular-session close.
- **Open:** a regular-session price whose `feedUpdateTimestamp` falls in the first minute of the next valid regular session.
- Windows are half-open: `[start, end)`.

Next live weekend — Epoch "TSLA 2026-W40":
- Friday 2026-10-02 is a full trading session, and Monday 2026-10-05 is the next regular session.
- Pyth's TSLA schedule lists no holiday or early close on 10-02 or 10-05. Its next holiday is `1126/C`, and the next early closes are `1127` and `1224`.
- Daylight-saving time applies (EDT = UTC−4) until 2026-11-01.

| Field | ET | UTC | Unix |
|---|---|---|---|
| `saleCutoff` | Fri 15:55 EDT | 2026-10-02T19:55:00Z | 1790970900 |
| `closeWindowStart` | Fri 15:59 EDT | 2026-10-02T19:59:00Z | 1790971140 |
| `closeWindowEnd` | Fri 16:00 EDT | 2026-10-02T20:00:00Z | 1790971200 |
| `openWindowStart` | Mon 09:30 EDT | 2026-10-05T13:30:00Z | 1791207000 |
| `openWindowEnd` | Mon 09:31 EDT | 2026-10-05T13:31:00Z | 1791207060 |
| `settlementDeadline` | Thu 09:31 EDT | 2026-10-08T13:31:00Z | 1791466260 |

`settlementDeadline = openWindowEnd + 72h` for live epochs; demo epochs use minutes.

Operator rules for future epochs:
- Derive windows from the feed's `America/New_York` schedule string, never from "next Monday".
- On an early-close day (e.g. 1127 or 1224, closing at 13:00 ET), use a 12:59–13:00 ET close window.
- If Monday is a holiday, move the open window to the next regular session (e.g. Tuesday).
- Convert ET to UTC with IANA rules.

Demo epochs (SnapshotOracle) use the same fields with compressed relative windows (minutes) and are labeled TESTNET DEMO.

**Timing consequence:**
- W40's Monday open (2026-10-05T13:30Z) is **after** the submission cutoff under any timezone reading of `Oct 4,2026 15:59`.
- A real-weekend epoch can therefore show the purchase and the Friday close before submission. Its Monday settlement happens after submission but before judging (Oct 12).
- The full lifecycle demo before submission has to use SnapshotOracle demo epochs.

Documented uncertainties (they don't affect storage or interfaces):
- The Pyth regular-session aggregate is not the official NYSE closing or opening auction print. This basis risk has to be disclosed to users.
- How Pyth sets `marketSession` exactly at the 16:00:00 and 09:30:00 ET boundaries is unverified until a real payload is inspected.
- A 60-second window still lets the submitter choose which price inside it to use. With operator-gated settlement in the MVP, that discretion is limited but not eliminated.

## 9. Approved architecture deltas (P1–P6) — Phase 1 storage & interface freeze

Approved by the owner on 2026-10-01. These fill gaps the architecture leaves open. Where they apply, they govern Phase 1.

### P1 — Premium escrow until successful settlement
- Pool tracks:
  - internal `lpAssets` (not `balanceOf`, so donations can't affect it);
  - `reservedLiability`;
  - `protocolFeesAccrued`;
  - `pendingPremium` (escrow): premium neither allocated by settlement nor refunded. It may include unclaimed refunds from earlier voided epochs, and it is never reset to zero;
  - `claimablePayouts` (P7): settled buyer money awaiting claims.
- ERC-4626 `totalAssets() = lpAssets`, with an OpenZeppelin virtual-share offset (inflation-attack resistance).
- **Premium is escrowed and excluded from LP-owned assets until successful settlement.**
  - On success, only that epoch's premium leaves escrow:
    - `pendingPremium -= epoch.premiumCollected`;
    - `protocolFee = floor(epoch.premiumCollected × protocolFeeBps / 10_000)` (`protocolFeeBps = 1200`);
    - `protocolFeesAccrued += protocolFee`;
    - `lpAssets += epoch.premiumCollected − protocolFee` (88% economics).
  - On a valid void, premium is refundable to policy holders (P2).
- `freeCollateral = lpAssets − reservedLiability`. This is equivalent to architecture §7, because `lpAssets` excludes fees and escrow.
- Purchase capacity requires both:
  - `reservedLiability + maxPayout ≤ lpAssets × utilizationCapBps / 10_000`;
  - `epoch.soldLiability + maxPayout ≤ epoch.maxAggregateLiability`.

### P2 — Settlement deadline and deterministic void
- New epoch field `settlementDeadline` (uint64), with `settlementDeadline > openWindowEnd`.
- `settleClose` / `settleOpen` succeed only while `block.timestamp < settlementDeadline`.
- `voidEpoch(epochId)`:
  - **permissionless and deterministic**;
  - succeeds only when `block.timestamp ≥ settlementDeadline` and the epoch is not `Settled`;
  - before the deadline, nobody (including the admin) can void.

  Settlement and void windows are disjoint, so the two can never race (boundary approved by owner).
- Voiding:
  - releases the epoch's whole `soldLiability` from `reservedLiability`;
  - leaves `premiumCollected` in escrow for refunds.
- `claim(policyId)` on a voided epoch:
  - marks the policy claimed (once);
  - `pendingPremium -= policy.premiumUSDG`;
  - transfers that premium to the receipt owner.

  The same `claimed` flag prevents a second claim. Refunds of a voided epoch can still be claimed after later epochs open or settle; later settlements never touch them.
- `EpochStatus`: `None, Open, CloseRecorded, Settled, Voided`.
  - Selling vs. locked is derived from `block.timestamp` vs. `saleCutoff`.
  - At most one epoch may be in `Open` or `CloseRecorded`.
- Live epochs use `settlementDeadline = openWindowEnd + 72h`; demo epochs use minutes.

### P3 — Per-epoch oracle adapter
- The epoch config freezes `address oracle` at creation; it is immutable afterwards.
- One pool can run TESTNET DEMO SnapshotOracle epochs and, if entitlement arrives, Pyth epochs.
- The oracle used is verifiable on-chain for each epoch.

### P4 — Oracle interface; the pool is the state-machine authority
```solidity
interface IReferenceOracle {
    /// Verifies vendor-specific `updateData` as a reference for `feedId` inside [windowStart, windowEnd)
    /// and returns normalized reference data. Must revert on any failed check.
    /// price: > 0, in the asset's fixed exponent. referenceTime: unix seconds (Pyth: feedUpdateTimestamp / 1e6).
    /// evidence: hash binding the accepted vendor evidence (e.g. keccak256 of the signed update).
    function verifyReference(bytes32 feedId, uint64 windowStart, uint64 windowEnd, bytes calldata updateData)
        external payable returns (uint256 price, uint64 referenceTime, bytes32 evidence);
}
```
- **`ProtectionPool` is the settlement state-machine authority.**
  - `settleClose(epochId, updateData)` and `settleOpen(epochId, updateData)` (architecture §8) call `epoch.oracle.verifyReference(...)`.
  - The pool then re-checks that `referenceTime` is in the window and `price > 0`, records the reference exactly once, and advances the status.
  - Adapters hold no settlement state and cannot call into the pool.
- **Future Pyth fee support.** Both settle functions are `payable` and forward `msg.value` to the adapter. The Pyth verifier's fee is currently 1 wei. Adapters that charge no fee (SnapshotOracle) must reject `msg.value > 0`.
- SnapshotOracle (TESTNET DEMO):
  - the owner posts snapshots on-chain with an event;
  - `updateData` references a stored snapshot, and prices are never supplied inline at settlement.
- Integer seconds make the half-open window check exact: `floor(µs / 1e6) < end ⟺ µs < end × 1e6`.

### P5 — Frozen storage

**Epoch config** (immutable after `createEpoch`):

| Field | Type |
|---|---|
| `assetId` | `bytes32` |
| `oracle` | `address` |
| `saleCutoff`, `closeWindowStart`, `closeWindowEnd`, `openWindowStart`, `openWindowEnd`, `settlementDeadline` | `uint64` |
| `triggerBps`, `maxCoverBps`, `premiumBps`, `protocolFeeBps` | `uint16` |
| `minNotional`, `maxNotional`, `maxAggregateLiability` | `uint256` |

**Epoch running state:** `soldNotional`, `soldLiability`, `premiumCollected` (all `uint256`).

**Epoch settlement state:**
- `closePrice`, `openPrice` (`uint256`);
- `closeTime`, `openTime` (`uint64`);
- `gapBps`, `coveredBps` (`uint16`);
- `closeEvidence`, `openEvidence` (`bytes32`);
- `status` (`EpochStatus`).

**Settlement (O(1), no loops):**
- `gapBps = Fc > Mo ? floor((Fc − Mo) × 10_000 / Fc) : 0`
- `coveredBps = min(max(gapBps − triggerBps, 0), maxCoverBps)`
- `actualOwed = floor(soldNotional × coveredBps / 10_000)`
- `reservedLiability −= soldLiability`; `lpAssets −= actualOwed`; `claimablePayouts += actualOwed` (P7)

Because every notional is a whole USDG amount (§7), each per-policy payout is exact. Their sum equals `actualOwed`, with no rounding dust, so `claimablePayouts` drains to zero.

Required Phase 1 tests for P1/P2/P5 (also in Architecture §16):
- non-whole-USDG notional rejected;
- `owed` equals the sum of individual payouts across multiple policies;
- settlement decreases `pendingPremium` by exactly that epoch's premium;
- void refunds decrement `pendingPremium` once per policy;
- an earlier voided epoch's refundable premium cannot be allocated by a later epoch's settlement.

**Policy** (immutable at purchase except `claimed`): `epochId`, `notional`, `premiumUSDG`, `maxPayout`, `claimed`. The claimant is `ProtectionReceipt.ownerOf(policyId)`.

**Pool:**
- immutables: `usdg`, `receipt`, `utilizationCapBps = 5000`;
- state: `lpAssets`, `reservedLiability`, `protocolFeesAccrued`, `pendingPremium`, `claimablePayouts` (P7), `activeEpochId`, `nextEpochId`, `nextPolicyId`, `settlementOperator`;
- OpenZeppelin `Pausable`.

**Asset** (architecture §7): `oracleFeedId`, `symbol`, `priceDecimals`, `enabled`.

### P6 — Rounding, pause, administration, receipt

**Rounding:** premium rounds **up**; `maxPayout`, payout and the protocol fee round **down**.

**Pause** blocks new risk and configuration:
- `buyProtection`, `createEpoch`, asset configuration;
- `deposit` (new LP capital is new risk; approved by owner).

**Pause never blocks:**
- valid `settleClose` / `settleOpen`;
- `voidEpoch`;
- `claim`;
- `withdraw` of free collateral.

**Administration** is kept simple:
- `Ownable2Step` owner: `createEpoch`, asset config, pause/unpause, `setSettlementOperator`, protocol-fee withdrawal from `protocolFeesAccrued` only;
- `settlementOperator` calls `settleClose` / `settleOpen`.

There is no admin void, and no admin path to escrow, reserved liability or LP assets.

**LP gating:**
- deposits are allowed only when no epoch is active, or before `saleCutoff`;
- withdrawals are blocked from `saleCutoff` until `Settled` / `Voided`, and are otherwise limited to `freeCollateral` (`maxWithdraw` / `maxRedeem` overrides).

**ProtectionReceipt:**
- OpenZeppelin ERC-721, with `tokenId == policyId` (unique);
- only the pool can mint;
- any transfer between nonzero addresses reverts (`_update` override).

### P7 — Settled payouts leave LP-owned assets (`claimablePayouts`)

Approved by the owner on 2026-10-01, before Phase 2. Found while implementing Phase 1.

**Problem.** Under P1–P6 as written, settlement released only `soldLiability − owed` and left `owed` inside `lpAssets` until claimed. Between settlement and claim, ERC-4626 share prices would include money already owed to buyers:
- an LP depositing after settlement would buy in at an inflated price and absorb part of the claims;
- an LP exiting early would receive more per share than is fair.

**Decision.** Add a global `uint256 claimablePayouts`: settled buyer money awaiting claims. It is not LP-owned, not protocol fees, not premium escrow, not free collateral, and it never increases selling capacity.

On successful settlement:
- `actualOwed = (epoch.soldNotional × coveredBps) / 10_000`
- `reservedLiability −= epoch.soldLiability`
- `lpAssets −= actualOwed`
- `claimablePayouts += actualOwed`
- `pendingPremium −= epoch.premiumCollected`
- `protocolFee = (epoch.premiumCollected × epoch.protocolFeeBps) / 10_000`; `protocolFeesAccrued += protocolFee`
- `lpAssets += epoch.premiumCollected − protocolFee`

Each successful policy claim:
- computes that policy's payout;
- marks the policy claimed before transfer;
- `claimablePayouts −= payout` (exactly);
- transfers the payout to the receipt owner.

A zero-payout settled policy is still finalized once: marked claimed, nothing transferred, `claimablePayouts` unchanged.

Voided-epoch premium refunds use `pendingPremium` only and never `claimablePayouts`.

**Why it is exact.** With whole-USDG notionals (§7), `actualOwed` equals the sum of individual payouts, so `claimablePayouts` drains to exactly zero after all claims. Immediately before successful settlement of the active epoch, `actualOwed ≤ epoch.soldLiability ≤ reservedLiability ≤ lpAssets`, so settlement cannot underflow. This is a precondition of settlement, not an invariant afterwards: settlement intentionally changes `reservedLiability` and `lpAssets`.

## 10. Source-of-truth updates (applied in commit "docs: freeze phase 0 architecture decisions")

`GAPSHIELD_PRODUCT_ARCHITECTURE.md` now states P1–P6 directly, so an implementer cannot work from stale architecture:
- §4 component responsibilities and vendor-neutral `IReferenceOracle`, with a Pyth note;
- §7 ER diagram, pool/epoch fields, rounding, purchase checks, and a new "Settlement, premium allocation, and void" subsection;
- §8 operations;
- §9 settlement sequence (pool calls oracle);
- §11 roles and pause semantics, plus threat-model rows;
- §13 events;
- §16 tests;
- a pointer to this document.

Verified corrections:
1. ZeroDev network listed (Architecture §3, §20; Brief §15, §16).
2. Pyth `feedUpdateTimestamp` + `marketSession` (Architecture §4, §11; Brief §15).
3. Deadline timezone not verified (Architecture §20).

This document remains the rationale and audit trail.

## 11. Remaining risks (genuine, unresolved — none affect Phase 1 storage or interfaces)

| Risk | Impact | Owner / action |
|---|---|---|
| HackQuest timezone unknown; registration closes `Oct 2,2026 17:01` | Missed registration or submission | User: register now; read the T&C PDF; submit ≥ 24h early |
| Pyth entitlement for equity feeds unknown | Pyth adapter may not ship | User: create a Pyth Terminal key. SnapshotOracle path unaffected |
| Historical `evm`-format signed payloads unverified | Historical replay via Pyth may be impossible | Phase 2 probe |
| Testnet ETH/USDG faucet limits unverified (both faucets refused automated fetches) | Demo pool may be small | User: claim test ETH + USDG for deployer and 2 demo wallets |
| No deployer wallet exists yet | Blocks Phase 2 deployment | User: `cast wallet import <name> --interactive` |
| USDG is an upgradeable, pausable external token | Transfers may revert if Paxos pauses | Phase 1: SafeERC20; document |
| Pyth aggregate ≠ official auction print; session-boundary behavior unverified | Basis risk in reference | Disclose; inspect a real payload in Phase 2 |

## 12. Phase 1 readiness

| Check | Result |
|---|---|
| Network, chain ID, USDG address and decimals verified | PASS |
| Asset and feed ID fixed (`bytes32(uint256(1435))`, exponent −5) | PASS |
| Economic parameters and rounding frozen | PASS |
| Reference windows and `settlementDeadline` defined for the demo weekend | PASS |
| Deltas P1–P6 approved | PASS |
| Can Pyth entitlement change Phase 1 storage? | No. It only changes which oracle address an epoch uses (P3) |
| Can ZeroDev, the HackQuest timezone or faucet limits change Phase 1 storage? | No |
| Can reference-semantics uncertainty change Phase 1 storage? | No. Windows are per-epoch data |
| **Phase 1 storage/interface decisions frozen** | **PASS** |
