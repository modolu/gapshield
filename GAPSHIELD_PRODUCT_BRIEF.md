<!-- PRODUCT_BRIEF.md -->
# GapShield — Product Brief
Version 0.1 · 2026-10-01 · Hackathon MVP / Product thesis · Owner: GapShield team

## 1. TL;DR

GapShield is fixed-price, on-chain weekend downside protection for tokenized-equity holders. A user chooses a stock, covered notional, trigger, and payout cap before Friday’s cutoff; if the underlying equity opens Monday below Friday’s reference by more than the trigger, GapShield pays the excess loss in USDG from a fully collateralized underwriting pool. The initial user is a non-US retail holder of tokenized US stocks who cannot or does not want to use traditional options, while the second user is a USDG liquidity provider willing to earn premium for taking bounded weekend risk. GapShield wins by doing one job clearly: protect the Friday-close-to-Monday-open gap without Greeks, margin, leverage, or active hedging.

## 2. The Problem

### Who has it

The primary user holds tokenized US-equity exposure through an on-chain venue and keeps positions over the weekend. Their token can remain transferable or tradeable while the underlying US equity market is closed, but the official equity reference still follows defined market sessions. Pyth’s current market-hours documentation lists US equities as open weekdays from 9:30 AM to 4:00 PM ET and closed on weekends, with separate pre-market, post-market, and overnight sessions.

This creates a structural close-to-open risk window. A lawsuit, guidance cut, regulatory action, product recall, geopolitical event, executive departure, or macro shock can occur while the primary market is closed. The Monday opening print can then be materially different from Friday’s close.

The problem is not that every weekend gaps. The problem is that the user cannot know which weekend will matter, and the loss is discontinuous: a stop order cannot guarantee an execution price through a gap.

### What they do today

Users currently choose among four imperfect responses:

1. **Hold and hope.** Zero direct cost, but full weekend event risk remains.
2. **Sell on Friday and rebuy later.** This reduces gap exposure but creates two trades, possible spread/slippage, potential tax or accounting consequences, and foregoes upside if nothing bad happens.
3. **Trade the token on the weekend.** This can be useful for price discovery, but weekend liquidity may be thinner and token prices can diverge from the underlying reference. Binance Research has reported that tokenized stocks can anticipate Monday moves, which reinforces that the token itself may reprice over the weekend; GapShield therefore does not assume the weekend token price is “wrong.”
4. **Use traditional options or on-chain options.** This is the closest economic substitute, but it adds strike selection, expiry choice, option approval/access, premium discovery, potentially 100-share contract conventions in traditional markets, and a broader derivatives interface than the user needs.

### Why existing solutions fail this user

The user’s actual question is simple:

> “If this stock opens badly on Monday, what is the most I can lose from the first X% of that gap?”

Traditional options can answer that question, but with more product complexity than necessary. Generic on-chain options protocols are designed to expose a full options market, not one recurring market-closure risk. Selling the token on Friday removes both downside and upside. Weekend token trading requires active monitoring and exposes the user to weekend liquidity conditions.

GapShield packages one event, one price, one trigger, and one bounded payout.

### Evidence the problem is real

The tokenized-equity market is still early, but it is no longer theoretical. CoinGecko reported the spot tokenized-stock market at roughly $487 million by the end of Q1 2026. Dune research has also highlighted that tokenized-equity turnover differs materially from perpetual markets and that weekend activity is affected by underlying market closure.

Adjacent builders already target the same structural blind spot from different angles:

- **Gapguard** protects tokenized-stock liquidity providers by dynamically increasing Uniswap v4 fees while traditional markets are closed.
- **LATCH** exposes market-hours and stale-oracle risk as analytics for tokenized equities.
- **Denar** freezes certain lending-market actions when equity oracles are paused.
- **Plume** builds fully collateralized options on tokenized equities.

Those products validate the risk category. GapShield is differentiated by protecting the **holder’s close-to-open downside** through a fixed-price, single-purpose parametric contract.

Source notes:
- Pyth market hours: `https://docs.pyth.network/price-feeds/pro/market-hours`
- CoinGecko tokenized-stock overview: `https://www.coingecko.com/learn/what-are-tokenized-stocks`
- Gapguard: `https://www.hackquest.io/projects/Gapguard`
- LATCH: `https://latchprotocol.com/`
- Plume: `https://github.com/PlumeTrade/Plume`

## 3. Vision & Mission

### Vision

In five years, any tokenized real-world asset can carry an optional, machine-readable risk layer at the moment of purchase, custody, lending, or collateralization. A user should be able to hold the asset they want while separately buying protection against a precisely defined event: market reopen, earnings release, holiday closure, corporate action, or other measurable trigger.

GapShield becomes the risk primitive that brokers, wallets, lending markets, and tokenization platforms embed rather than a destination users must discover.

### Mission

Make event risk on tokenized real-world assets understandable, fixed-price, fully collateralized, and automatically settled.

### Product principles

1. **One event, one number, one decision.** A user must understand the protection without learning option Greeks.
2. **Bounded risk on both sides.** The buyer knows premium and maximum payout; the underwriter knows maximum aggregate liability before accepting risk.
3. **Collateral before promises.** No protection may be sold unless the pool can cover the worst-case payout.
4. **Oracle evidence over discretion.** Claims are settled by a defined reference window and deterministic math, not a human claims process.
5. **No hidden weekend repricing assumption.** Weekend token prices may contain information. GapShield protects a defined official close-to-open move; it does not claim weekend token prices are invalid.
6. **Prototype honestly, mainnet cautiously.** The hackathon build is testnet financial infrastructure. Regulatory, oracle, and security gates must be satisfied before real money is accepted.

## 4. Target Users

### Primary persona — “The global tokenized-stock holder”

**Context:** A non-US user in Singapore, Southeast Asia, Europe, Africa, or another market where tokenized US-equity exposure is easier to access than a full US brokerage/options account. They hold stock tokens for days or weeks rather than day-trading them.

**Goals**
- Keep exposure through the weekend.
- Know the maximum covered part of a bad Monday gap.
- Avoid learning options mechanics.
- Avoid margin, liquidation, and active hedge management.
- Pay a known premium once.

**Frustrations**
- Traditional markets close while news does not.
- A stop-loss does not guarantee a fill through a gap.
- Weekend token liquidity may be thin.
- Existing on-chain derivatives interfaces are built for traders.
- Traditional options access may be unavailable, unfamiliar, or operationally cumbersome.

**Tools**
- Mobile wallet / smart account
- Tokenized-equity venue
- Stablecoin balance
- Price apps / portfolio tracker

**Representative quote**

> “I want to keep my stock through the weekend. I just don’t want one headline to turn Monday morning into a 10% surprise.”

### Secondary persona — “The USDG underwriter”

**Context:** A DeFi user with idle USDG or stablecoin capital who already understands lending pools and yield.

**Goals**
- Earn premium for taking explicit, capped risk.
- See pool utilization and maximum liability before depositing.
- Know exactly when funds are locked and when they become withdrawable.
- Avoid hidden leverage or uncapped loss.

**Frustrations**
- Lending yields compress.
- Many yield products obscure the actual source of return.
- Underwriting products can hide tail risk.

**Representative quote**

> “Tell me the worst-case loss, the utilization, and the premium. I’ll decide whether the yield is worth the risk.”

### Later persona — protocol risk manager

A lending market, vault, broker, or tokenized-stock platform that wants to buy weekend cover in bulk to reduce close-to-open liquidation or inventory risk.

### Anti-persona

GapShield v1 is **not** for:
- professional options traders who want a full volatility surface;
- leveraged speculators seeking a high-frequency binary betting venue;
- US retail customers requiring regulated securities/derivatives access;
- users seeking protection after bad weekend news is already public;
- institutions requiring bespoke OTC structuring in v1.

The product stays narrow because simplicity is the advantage.

## 5. Jobs To Be Done

Ranked by importance:

1. **When I plan to hold a tokenized stock over the weekend, I want to buy a known amount of downside protection before Friday’s cutoff, so I can keep my exposure without accepting the full Monday-open gap.**
2. **When I buy protection, I want to know the premium and maximum payout before signing, so I can decide whether the hedge is worth it.**
3. **When Monday opens, I want settlement to happen from a verifiable market reference, so I do not need to file a claim or trust a claims adjuster.**
4. **When I provide USDG liquidity, I want the contract to cap total liabilities below pool collateral, so a large gap cannot create insolvency beyond my deposited capital.**
5. **When I provide liquidity, I want to see when my capital is reserved and when it becomes withdrawable, so I can manage liquidity without hidden lockups.**
6. **When I use GapShield on mobile, I want the transaction flow to feel like buying a simple protection add-on, so I do not need DeFi expertise.**

## 6. Market & Competitive Landscape

### Market size

A broad “options TAM” would be misleading. GapShield’s near-term market should be measured from **covered notional**, not total global equity derivatives volume.

CoinGecko reported approximately **$487M in spot tokenized-stock market value at the end of Q1 2026**. The category is expanding quickly, but current AUM is still too small and volatile for a precise long-range TAM claim.

#### Bottom-up revenue model

Let:

- `N` = annual average tokenized-equity notional users are willing to protect;
- `W` = average number of protected weekends per year;
- `P` = average premium as a percentage of notional per protected weekend;
- `F` = GapShield protocol fee share of premium.

Annual protocol revenue:

`Revenue = N × W × P × F`

Illustrative, not forecast:

| Protected notional | Protected weekends/year | Avg premium | Protocol fee | Annual protocol revenue |
|---:|---:|---:|---:|---:|
| $10M | 20 | 0.50% | 12% | $120k |
| $100M | 20 | 0.50% | 12% | $1.2M |
| $500M | 20 | 0.50% | 12% | $6.0M |
| $1B | 26 | 0.45% | 12% | $14.0M |

#### SAM

The initial serviceable market is non-US holders of tokenized US stocks on EVM-compatible venues where:
- USD-denominated stock exposure exists;
- users can hold over weekends;
- oracle/reference data can settle close-to-open events;
- the legal distribution path permits the product.

#### SOM

The first 12-month target should be operational rather than market-share based:
- 500 active protection buyers;
- $5M cumulative covered notional;
- $250k+ underwriting liquidity;
- one embedded B2B integration.

### Competitor table

| Alternative | Strengths | Weaknesses for our user | Pricing model | GapShield edge |
|---|---|---|---|---|
| Traditional put options via Robinhood/IBKR/etc. | Deep, established markets; flexible strikes/expiries | Access/approval varies; complex UX; often broader than needed | Market premium/spread | One recurring event, fixed quote, stablecoin settlement |
| Plume / tokenized-equity options | On-chain, fully collateralized, general-purpose options | Still an options market with strike/expiry decisions | Option premium | Purpose-built close-to-open cover |
| Premia / generic on-chain options | Mature options primitives | Primarily crypto/general-purpose, trader-oriented | Pool/orderbook premium | Retail RWA closure-risk UX |
| Gapguard | Directly addresses closed-market risk for LPs | Protects LP economics, not stock-holder losses | Dynamic swap fees | Buyer-facing payout protection |
| LATCH | Clear risk analytics and market-status visibility | Does not transfer risk or pay the holder | Analytics/API | Pays deterministic USDG protection |
| Denar | Market-aware lending controls | Reduces lending risk, not holder gap loss | Lending spread | Direct protection for the holder |
| Sell Friday / rebuy later | Simple, no new product | Loses upside; two trades; spread/fees | Trading costs | Keep exposure and cap part of gap |
| Hold and hope | Free | No protection | None | Known premium for bounded cover |

### Positioning statement

For non-US tokenized-equity holders who want to stay invested through market closure, **GapShield** is a fixed-price parametric protection product that pays USDG when the underlying equity’s Monday open breaches a predefined downside gap. Unlike traditional or on-chain options, GapShield is designed around one recurring job: **protect the weekend without Greeks, margin, or active hedging.**

### Why now

Three shifts make this possible now:

1. Tokenized equities have reached meaningful on-chain availability.
2. Robinhood Chain is an EVM-compatible Arbitrum L2 focused on financial products and supports standard Solidity tooling.
3. Oracle infrastructure such as Pyth exposes equity feeds and EVM verification on Robinhood Chain/Arbitrum networks, while USDG is deployed on Robinhood and Arbitrum networks.

## 7. Value Proposition & Differentiation

### The wedge

> **Protect a tokenized stock specifically against the Friday-close-to-Monday-open downside gap, at a fixed known price, before the weekend starts.**

This is narrower than options and more actionable than risk analytics.

### The “magic moment”

It is Monday morning.

The user opens GapShield after a bad weekend headline. Their stock opens 8.4% below Friday’s reference. The policy card changes from **Protected** to **Triggered** and shows:

- Friday reference: $100.00
- Monday open: $91.60
- Gap: −8.40%
- Trigger: −5.00%
- Covered excess: 3.40%
- Payout: 34.00 USDG
- Status: **Claimable**

The user taps **Claim 34 USDG**. There is no form, evidence upload, support ticket, or option exercise decision.

### Moat

1. **Risk data:** close-to-open distributions, realized loss, premium adequacy, demand by asset.
2. **Liquidity:** consistent underwriter capital and utilization history.
3. **Distribution:** embedded checkout inside wallets, brokers, lending markets, and vaults.
4. **Pricing calibration:** better asset/event-specific pricing over time.
5. **Trust:** audited settlement logic and a record of paying exactly when promised.
6. **B2B integration:** APIs for protocols to protect collateral or inventory.

## 8. Scope

### MVP (v1)

| Feature | Job served |
|---|---|
| One supported equity risk market, initially TSLA if oracle verification succeeds | Prove one real market instead of fake breadth |
| One weekly protection epoch | Model the exact Friday-to-Monday job |
| Fixed trigger, cap, notional, premium quote | Make cost and payout understandable |
| USDG underwriting vault | Provide real collateral |
| Fully collateralized liability accounting | Prevent insolvency |
| Hard sales cutoff | Prevent adverse selection |
| Non-transferable on-chain protection receipt | Ownership/claim proof without secondary-market scope |
| Close/open settlement through oracle adapter | Deterministic event resolution |
| Automatic payout calculation + claim | Deliver magic moment |
| Underwriter dashboard | Make liability and utilization legible |
| Testnet demo settlement mode | Reproduce both outcomes before deadline |
| Pause/emergency controls | Contain integration/oracle failure |
| Foundry unit, fuzz, invariant tests | Demonstrate contract quality |

### v2 and later

- multiple equities;
- multiple tiers;
- utilization-based premiums;
- automated weekly epochs;
- dual-oracle redundancy;
- protocol B2B API;
- guaranteed passkey/gasless onboarding;
- white-label checkout;
- earnings-event and holiday cover;
- institutional RFQ liquidity;
- LP tranches;
- Stylus/Rust pricing module;
- mainnet deployment.

### Out of scope

We will not build a full options exchange, perpetual venue, prediction market, leveraged/undercollateralized underwriting product, claims-adjustment business, secondary policy market, or retail mainnet derivatives product without legal/security review.

## 9. Key User Journeys

### Journey 1 — First-run onboarding

**Trigger:** User plans to keep a supported stock token over the weekend.

**Steps:** Open GapShield → connect wallet/smart account → tap **Protect my weekend** → enter notional → review trigger/cap/premium/examples → sign.

**Success:** Policy shows **Protected until Monday settlement**.

**Emotional goal:** “I understand exactly what I paid for.”

### Journey 2 — Buy protection

**Trigger:** User stays exposed through the weekend.

**Steps:** Select stock → enter $1,000 notional → see fixed tier → see premium → scrub three Monday scenarios → buy before cutoff.

**Success:** Transaction confirms and policy appears under “My protection.”

**Emotional goal:** Relief without feeling like they traded an option.

### Journey 3 — Monday settlement and claim

**Trigger:** Valid opening reference becomes available.

**Steps:** Oracle update submitted → contract computes gap → policy shows payout → user claims USDG.

**Success:** USDG lands with linked transaction evidence.

**Emotional goal:** “It did what it said it would do.”

### Journey 4 — Underwrite a weekend

**Trigger:** User has idle USDG.

**Steps:** Open Underwrite → inspect TVL, reserved liability, free collateral, premium → deposit → see vault position → wait through epoch → withdraw free capital after settlement.

**Success:** Premium accrues with bounded, visible risk.

**Emotional goal:** “I know the risk I am being paid to take.”

### Journey 5 — Judge demo

**Trigger:** Reviewer cannot wait for a real weekend.

**Steps:** Demo banner → buy test policy → calm scenario → reset → −12% scenario → claim.

**Success:** Full economic lifecycle is visible in under three minutes.

## 10. Experience & Design Direction

### Brand personality

- **Calm, not alarmist**
- **Precise, not terminal-dense**
- **Protective, not paternal**
- **Modern, not casino-like**
- **Transparent, not magical**

### Interaction principles

1. Show the payout graph before the buy button.
2. Translate every percentage into USD for the chosen notional.
3. Keep one sentence visible: “Pays the gap beyond 5%, capped at 5%.”
4. Never hide cutoff, oracle source, or max payout.
5. Show pool solvency in plain language.
6. Progressive disclosure for contract details.

### Signature details

**Payout scrubber:** drag a hypothetical Monday open and see payout update instantly.

**Weekend shield state:** protection card visibly changes to a shielded state after purchase.

**Solvency bar:** one bar shows collateral, reserved worst-case liability, free liquidity.

**Monday reveal:** Friday price + Monday price animate into the computed gap and payout. No confetti.

### Accessibility commitments

WCAG 2.2 AA:
- 4.5:1 text contrast;
- keyboard flow;
- visible focus;
- no color-only states;
- reduced-motion support;
- labeled financial inputs;
- 44×44px touch targets;
- semantic transaction status.

### Inclusive / localization

- mobile-first;
- local time plus ET for market cutoff;
- plain USD before basis points;
- translatable copy;
- no assumption user owns legal shareholder rights;
- low-bandwidth design with no mandatory charts.

## 11. Business Model

### Pricing and packaging

- Fixed premium paid in USDG.
- Default hackathon split: **88% of premium to underwriting economics / 12% protocol fee**.
- No buyer subscription in v1.

Future B2B:
- volume protocol fees;
- white-label API fee;
- risk-data subscription.

### Unit economics assumptions

Hypotheses:
- >80% gross margin on protocol fee after software/oracle costs at scale;
- first 500 users founder/community-led, cash CAC target <$20;
- 8–20 protected weekends/user/year;
- $500–$5,000 retail covered notional;
- 0.25–1.25% average premium depending on tier/asset.

Example:
- $2,000 notional
- 12 protected weekends/year
- 0.50% premium
- $120 annual gross premium
- $14.40 annual protocol revenue/user at 12% take.

This implies embedded B2B distribution is strategically important.

### Revenue milestones

1. $5M cumulative covered notional.
2. $100k gross premium processed.
3. $12k protocol revenue at 12% blended take.
4. One B2B partner drives >25% of covered notional.
5. Non-weekend risk products contribute >20% of premium.

## 12. Go-To-Market

### Launch strategy and channels

Start with:
- Robinhood Chain / Arbitrum RWA communities;
- tokenized-equity holders;
- DeFi users with USDG;
- lending/vault teams exposed to market-hour mismatch.

Lead with the problem, not “insurance.”

Content:
- weekly Friday gap watch;
- historical “what GapShield would have paid” calculator;
- transparent solvency dashboard.

### First 100 users

- 30 tokenized-stock holders;
- 20 test underwriters;
- 20 builders/founders;
- 10 RWA researchers/traders;
- 20 referrals.

### First 1,000

- wallet/venue embed;
- one issuer/venue/wallet partnership;
- one lending/vault integration;
- weekly historical risk reports.

### First 10,000

Distribution must be embedded:
- broker/venue checkout;
- wallet portfolio action;
- lending-market bulk cover;
- API/SDK.

### Growth loops

1. Protection-position sharing.
2. Weekly risk-content → quote.
3. More demand → more premium opportunity → deeper liquidity.
4. B2B integrations create recurring demand.

## 13. Success Metrics

### North Star

**Protected notional settled with full solvency.**

It captures use while forcing the product to honor its core promise.

### Inputs

- activated buyers/week;
- quote→purchase conversion;
- repeat rate;
- average protected notional;
- premium/notional;
- USDG TVL;
- free vs reserved collateral;
- utilization;
- settlement success;
- claim completion;
- failed transaction rate;
- mobile completion rate.

### Guardrails

- solvency ratio always ≥100% of worst-case liability;
- quote/payout mismatch = 0;
- policies sold after cutoff = 0;
- claim double-spend = 0;
- LP withdrawal into reserved funds = 0;
- contract exploit loss = $0.

### Targets

| Metric | 30 days | 90 days | 180 days |
|---|---:|---:|---:|
| Activated buyers | 100 | 500 | 2,000 |
| Cumulative protected notional | $250k | $5M | $25M |
| Underwriter liquidity | $50k target | $250k+ | $1M |
| Repeat buyer rate | 20% | 35% | 45% |
| B2B integrations | 0–1 pilots | 1 live | 3 live |
| Settlement success | 100% testnet | >99.9% | >99.9% |

Targets remain directional until legal/mainnet path is resolved.

## 14. Award & Recognition Strategy

### Arbitrum Open House Singapore — Overall

Published criteria:
- smart-contract quality;
- product-market fit;
- innovation/creativity;
- real problem solving;
- extra consideration for USDG;
- at least one of three overall prizes reserved for Robinhood Chain.

GapShield maps directly:
- **Contract quality:** solvency invariant, oracle windows, fuzz/invariant tests.
- **PMF:** narrow recurring weekend job.
- **Innovation:** event-specific parametric protection.
- **Problem:** close-to-open discontinuity.
- **USDG:** collateral, premium, payout.
- **Robinhood:** primary testnet deployment.

### Promising Products

Same criteria; GapShield is a direct fit as a narrow financial primitive with a credible distribution story.

### Milestone grant

Proposed milestones:
1. audit-ready contracts + production oracle;
2. compliant mainnet distribution path;
3. $250k+ seeded liquidity;
4. first protocol/broker integration;
5. first 500 paid policies.

### Post-hackathon recognition

Only after legally launchable:
- Product Hunt;
- Webby fintech/product categories;
- design awards only if production craft warrants them.

### Evidence to collect from day one

- 10–20 structured user interviews;
- first-time comprehension recordings;
- quote→purchase time;
- payout-comprehension test;
- invariant/fuzz results;
- testnet transaction links;
- underwriter risk comprehension;
- protocol testimonials;
- historical payout backtests.

## 15. Risks & Mitigations

| Risk | Type | Likelihood | Impact | Mitigation | Owner |
|---|---|---:|---:|---|---|
| Retail derivatives regulation blocks direct launch | Legal | High | Critical | Testnet only; legal counsel; prioritize B2B/regulated partner | Founder |
| Buy after bad weekend news | Adverse selection | High | Critical | Hard pre-weekend cutoff | Contracts |
| Pool sells more liability than collateral | Solvency | Low if correct | Critical | Atomic reserve + invariant tests + cap | Contracts |
| Oracle unavailable on chosen chain/feed | Technical | Medium | High | Oracle interface + labeled testnet fallback | Engineering |
| Wrong/stale reference window | Technical | Medium | Critical | Feed ID + publish-time window checks | Contracts |
| Demo oracle mistaken for production | Trust | Medium | High | Persistent TESTNET DEMO labeling | Product |
| LP interprets premium as risk-free yield | UX/legal | Medium | High | Always show worst-case liability | Product |
| Weekend token already reprices news | Market | High | Medium | Settle on defined underlying close/open; disclose basis risk | Product |
| Pricing underestimates loss | Market | Medium | High | Conservative fixed tiers + utilization cap | Risk |
| Too much scope misses deadline | Delivery | High | High | One stock, one epoch, one pool, one tier first | Lead |
| Gapguard/Plume comparison weakens novelty | Competitive | High | Medium | Buyer-vs-LP and parametric-vs-options differentiation | Founder |
| Admin key compromise | Security | Low | High | Testnet EOA; multisig/timelock before mainnet | Engineering |
| ZeroDev unsupported hosted chain | Integration | Medium | Medium | Standard wallet fallback | Frontend |

## 16. Assumptions & Open Questions

### Assumptions

1. Team size is unspecified. Plan assumes one primary builder with AI coding support and optional 1–2 collaborators.
2. TSLA is preferred for demo salience, but the asset will change if AAPL or another equity has cleaner oracle support.
3. USDG is fixed collateral/premium/payout asset.
4. Robinhood Chain Testnet is primary; Arbitrum Sepolia is an optional mirror.
5. Pyth is preferred, but exact equity feed access and historical/signed update semantics must be verified.
6. A trusted SnapshotOracle is acceptable only for an explicitly labeled testnet demo.
7. v1 protection receipts are non-transferable.
8. Testnet MVP does not prove buyer owns corresponding stock; mainnet design must revisit this.
9. Contract pricing is a fixed premium-bps tier informed by offline history.
10. No upgradeable proxy in hackathon MVP.
11. No “first” claim; adjacent products already exist.

### Open questions

1. Does the chosen Pyth equity feed verify on Robinhood Chain Testnet under available credentials?
2. What exact timestamps define Friday close and Monday open across DST/holidays?
3. Does ZeroDev hosted bundler/paymaster support Robinhood Chain Testnet?
4. Are sufficient Robinhood test ETH and USDG available for the judge demo?
5. What exact HackQuest repository/deployment evidence is mandatory?
6. Can “parametric protection” be used safely in pitch copy without implying licensed insurance?
7. Should mainnet require verified stock-token holdings?
8. What historical sample size is enough to set initial premium tiers credibly?
