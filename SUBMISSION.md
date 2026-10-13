# GapShield — Colosseum Crypto World's Fair Submission

**Protect the gap. Keep the exposure.**

> Submission working document. Keep every claim aligned with the current repository and deployed prototype.

GitHub: https://github.com/modolu/gapshield
Current deployed network: Robinhood Chain Testnet (46630)
Collateral / settlement asset: Paxos USDG
Live testnet evidence: [`docs/TESTNET_DEMO_EVIDENCE.md`](docs/TESTNET_DEMO_EVIDENCE.md)

## Important eligibility note

GapShield's current live prototype is deployed on **Robinhood Chain Testnet**, not Solana. Do not select Solana or describe GapShield as Solana-integrated unless a real Solana integration is completed before submission. This document preserves the project's actual current state so the submission does not overclaim.

---

## 1. Project details

### Project name

**GapShield**

### Tagline

**Protect the gap. Keep the exposure.**

### One-line description

**Fixed-price, fully collateralized downside protection for tokenized equities.**

### Project website

https://web-nu-three-12.vercel.app

### What are you building, and who is it for?

GapShield is an on-chain risk protection protocol for holders of tokenized equities. It helps investors protect against sharp downside gaps that can occur while the underlying stock market is closed, without requiring them to sell their position or use a complex options product.

Users purchase protection for a defined notional amount by paying a fixed USDG premium before a cutoff. Liquidity providers deposit USDG into a fully collateralized underwriting pool, and the protocol reserves the maximum possible liability as soon as protection is sold. When the protection window ends, reference prices are used to determine whether the predefined downside event occurred and, if triggered, the policy holder can claim the resulting USDG payout.

The current prototype focuses on one narrow event: the Friday-close to Monday-open downside gap in tokenized US equities. The first implementation protects downside beyond a 5% gap, capped at an additional 5%.

GapShield is initially built for tokenized-equity holders who want to remain invested through weekends while limiting discontinuous downside risk, and for stablecoin holders seeking transparent, bounded underwriting opportunities.

### Why did you decide to build this, and why build it now?

I decided to build GapShield because tokenizing equities changes how they can be held and transferred, but it does not remove the risks created by the underlying market structure.

A tokenized stock may remain transferable on-chain while the US equity market is closed. If meaningful news breaks during that period, the underlying stock can reopen substantially below its previous close. A traditional stop-loss cannot guarantee protection through a price gap, while the alternatives — exiting the position, relying on thin off-hours liquidity, or using conventional options — introduce additional complexity.

The timing matters because tokenized real-world assets are becoming increasingly usable on-chain, stablecoins provide practical settlement and collateral infrastructure, and smart contracts allow narrowly defined risks to be priced and fully collateralized.

That creates an opportunity for a new category of simple parametric risk products designed specifically for tokenized assets. GapShield starts with weekend downside gaps, but the broader thesis includes earnings events, market holidays and other objective event-driven risks.

### What technologies are you using or integrating with?

- Solidity 0.8.37
- Foundry
- OpenZeppelin 5.7
- ERC-4626 underwriting vault architecture
- ERC-721 non-transferable protection receipts
- Paxos USDG
- Robinhood Chain Testnet
- SnapshotOracle testnet adapter
- GitHub Actions CI
- Integer-only premium and payout math

Current production-safe oracle integration is **not complete**. `SnapshotOracle` is explicitly a **TESTNET DEMO ORACLE**.

### Which chains does your product use?

**Robinhood Chain Testnet only, in the current deployed prototype.**

Do not select Solana unless a real Solana deployment or integration is completed before final submission.

### How does your product use the chain?

GapShield uses Robinhood Chain Testnet for protection issuance, collateral custody, premium collection, liability reservation, deterministic settlement and USDG payout claims.

Liquidity providers deposit USDG into an on-chain protection pool. Buyers purchase protection through smart contracts, receive a non-transferable policy receipt, and can claim any resulting payout directly on-chain after settlement.

The blockchain provides transparent collateralization and verifiable accounting, while GapShield supplies the risk definition, policy lifecycle and settlement logic above it.

### Category

**Real World Assets (RWA)**

Secondary category if the form allows more than one: **DeFi**.

### Is your project a mobile-focused dApp?

**No.**

---

## 2. Current product wedge

The current product expresses one simple protection rule:

> **Pays the downside gap beyond 5%, capped at a further 5%.**

Prototype economics:

| Term | Value |
|---|---|
| Trigger | 5% downside gap |
| Maximum additional cover | 5% |
| Premium | 0.80% of protected notional |
| Premium split | 88% LP / 12% protocol |
| Policy size | 10–10,000 USDG |
| Utilization cap | 50% |
| Example | 1,000 USDG notional → 8 USDG premium → 50 USDG maximum payout |

These parameters are prototype terms, not actuarially validated production pricing.

---

## 3. How GapShield works

1. Liquidity providers deposit USDG into the ERC-4626 protection pool.
2. An epoch is opened with explicit sale, reference-price and settlement windows.
3. A buyer purchases protection before the cutoff and pays a fixed premium.
4. The pool reserves the maximum possible payout immediately.
5. Close and open reference prices are submitted through the epoch's oracle adapter.
6. Settlement deterministically calculates the covered gap and moves any payout into a claimable bucket.
7. The policy owner claims the payout in USDG.
8. If valid settlement never arrives before the deadline, anyone can void the epoch and buyers can reclaim their premium.

---

## 4. Live prototype proof

GapShield is deployed on Robinhood Chain Testnet using official Paxos USDG.

A complete on-chain lifecycle has been executed:

- LP deposit: **1,000 USDG**
- Protected notional: **1,000 USDG**
- Premium: **8 USDG**
- Maximum reserved payout: **50 USDG**
- Reference close: **100.00**
- Reference open: **91.00**
- Raw gap: **9%**
- Covered gap: **4%**
- Buyer payout: **40 USDG**
- Protocol fee: **0.96 USDG**
- LP premium allocation: **7.04 USDG**
- Final LP assets: **967.04 USDG**
- Claimable payouts after claim: **0 USDG**
- Reserved liability after settlement: **0 USDG**
- Pending premium after settlement: **0 USDG**

The final pool balance of **968 USDG** reconciles exactly as:

**967.04 USDG LP assets + 0.96 USDG protocol fees.**

Full transaction hashes and block numbers are recorded in [`docs/TESTNET_DEMO_EVIDENCE.md`](docs/TESTNET_DEMO_EVIDENCE.md).

### Deployed contracts

| Contract | Address |
|---|---|
| ProtectionPool | `0xA1De944d3d1247747a020AB7C325431D9221B13d` |
| ProtectionReceipt | `0x19573Ed5eee1D348626679737844E769527C1c46` |
| SnapshotOracle | `0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6` |
| Paxos USDG | `0x7E955252E15c84f5768B83c41a71F9eba181802F` |

---

## 5. Technical architecture

- `ProtectionPool`: ERC-4626 vault plus policy, reserve, settlement and claim state machine.
- `ProtectionReceipt`: non-transferable ERC-721 policy receipt with ERC-5192-style locked behavior.
- `PremiumMath` / `PayoutMath`: deterministic integer-only calculations.
- `IReferenceOracle`: oracle abstraction used by the pool.
- `SnapshotOracle`: trusted testnet-only adapter used for the live prototype.
- Separate accounting for LP assets, reserved liability, pending premium, claimable payouts and protocol fees.
- No proxy architecture.
- No loops over policies or LPs in the core lifecycle.
- Permissionless void path after the settlement deadline.

### Testing

- **208 Foundry tests passing** in the validated repository state.
- CI includes fuzz testing and a stateful invariant suite.
- The invariant suite checks 15 properties over 256 randomized sequences of 128 calls, totalling 32,768 calls in the recorded run.

The contracts are **unaudited**.

---

## 6. Oracle disclosure

The current live testnet demo uses **`SnapshotOracle`**, which identifies itself as a **TESTNET DEMO ORACLE**.

A trusted operator posts the reference prices. It is not decentralized, not a production market-data source and not presented as production-safe.

The core pool is oracle-agnostic through `IReferenceOracle`, so a future production adapter can replace the demo oracle without redesigning the core protection state machine.

---

## 7. Business model

The prototype allocates **12% of collected premium** to protocol fees and **88%** to LP economics after successful settlement.

The longer-term distribution thesis is embedded protection rather than requiring every user to discover a standalone insurance marketplace. Potential distribution surfaces include:

- tokenized-equity wallets
- tokenized-stock trading venues
- structured-product interfaces
- lending and collateral platforms

This is an early business-model hypothesis. GapShield has **no production revenue today**.

---

## 8. Target users

### Primary

Holders of tokenized US equities who want to remain exposed through weekends while limiting severe close-to-open downside risk.

### Secondary

Stablecoin holders willing to underwrite explicitly capped event risk in exchange for premium income.

### Longer-term distribution users

- wallets
- tokenized-equity venues
- lending protocols
- structured-product platforms

---

## 9. Why this can become larger than the first wedge

GapShield is not trying to recreate a full options exchange.

The thesis is narrower: as real-world assets move on-chain, users will need simple protection products that match the risks of those assets without forcing them into traditional derivatives complexity.

Weekend gaps are the first wedge because the event is bounded, objectively measurable and easy to explain. The same architecture can later support other event-defined risks such as:

- earnings gaps
- holiday gaps
- scheduled event risk
- other bounded downside events in tokenized real-world assets

The long-term opportunity is a **parametric risk layer for tokenized assets**.

---

## 10. Notes for judges

### Did anyone not listed on the team do meaningful work?

**No.** GapShield was built and developed independently by the listed founder. External developer tools, AI-assisted development tools and third-party infrastructure were used during development, but no unlisted person acted as a project team member or independently performed meaningful project work.

### Pre-existing work disclosure

GapShield existed before this Colosseum submission effort and is **not being represented as a project created entirely from scratch during Colosseum**.

The current repository was initialized on **October 1, 2026**, and the live Robinhood Chain Testnet prototype, USDG integration, settlement/claim lifecycle and original submission documentation were completed before this Colosseum-specific submission preparation.

For transparency, the last repository state before Colosseum-specific submission work is:

- **Commit:** `8b262b7`
- **Date:** 2026-10-03
- **Commit message:** `docs: mark submission checks complete`

Colosseum-period submission work should be described only as the actual work completed after that baseline, including any genuine product changes, new integrations, reliability work, UX work, additional validation, deployment changes, positioning or documentation completed during the competition period.

Do not imply that pre-existing contracts, tests or deployments were created during Colosseum if they were not.

---

## 11. Important context about the repository

This repository contains the complete current GapShield prototype, including:

- core protection contracts
- protection receipt contract
- oracle interface and testnet oracle
- deployment tooling
- automated tests
- Robinhood Chain Testnet deployment manifest
- live transaction evidence
- product architecture and product brief
- deployment documentation

Judges should primarily review:

1. `README.md`
2. `contracts/`
3. `test/`
4. `docs/TESTNET_DEMO_EVIDENCE.md`
5. `docs/DEPLOYMENT.md`
6. `deployments/46630.json`

Pre-Colosseum baseline: **`8b262b7`**.

---

## 12. GitHub link

https://github.com/modolu/gapshield

If the repository becomes private before submission, invite `hackathon@colosseum.com` and verify access before submitting.

---

## 13. Demo video

### Recommended length

**1:30–2:00**

### Recommended sequence

1. GapShield opening card.
2. Explain the weekend-gap problem.
3. Show the protection rule and product mechanics.
4. Show the live deployment.
5. Show the 1,000 USDG LP deposit.
6. Show the 1,000 USDG protection purchase and 8 USDG premium.
7. Show the 100 → 91 settlement and 40 USDG calculated payout.
8. Show the 40 USDG on-chain claim.
9. Show the reconciled final accounting.
10. End on: **Protect the gap. Keep the exposure.**

### Demo voiceover

> Tokenized equities can remain transferable on-chain while the market that prices the underlying stock is closed. If bad news lands during that period, the stock can reopen far below its previous close, and a stop-loss cannot protect an investor through that gap.
>
> GapShield provides fixed-price, fully collateralized protection for that specific risk.
>
> Liquidity providers deposit USDG into a protection pool. A holder chooses how much exposure to protect and pays a known premium before the cutoff. The protocol immediately reserves the maximum possible payout.
>
> In this live testnet example, an underwriter deposited one thousand USDG. A buyer then protected one thousand USDG of TSLA exposure for an eight USDG premium, with fifty USDG reserved as the maximum payout.
>
> The reference price moved from one hundred dollars to ninety-one dollars — a nine percent gap. Protection starts beyond five percent, so four percent was covered, producing a forty USDG payout.
>
> The buyer then claimed exactly forty USDG on-chain.
>
> After the claim, the accounting reconciled exactly: nine hundred and sixty-seven point zero four USDG belonged to LPs, ninety-six cents was accrued as the protocol fee, and nothing remained claimable, reserved or escrowed.
>
> The current prototype uses an explicitly labelled testnet demo oracle, not a production price feed.
>
> GapShield turns a difficult market discontinuity into simple, bounded protection: protect the gap, keep the exposure.

### Show demo video on public project page

**Yes.**

### Demo video URL

**TBD — add final YouTube/Loom/Vimeo URL.**

---

## 14. Live product link and access instructions

### Live product URL

https://web-nu-three-12.vercel.app

### Access instructions

The public Vercel site is a lightweight product landing page for the current testnet prototype. No wallet connection or funding is required to review it.

For the complete working proof, judges should use the repository and explorer links to inspect the deployed Robinhood Chain Testnet contracts, transaction history, policy lifecycle, settlement and accounting evidence.

The current settlement implementation uses `SnapshotOracle`, an explicitly labelled **TESTNET DEMO ORACLE** operated by a trusted account. It is not presented as a production market-data oracle.

---

## 15. Pitch video

### Recommended length

**60–90 seconds**

### Pitch script

> Hi, I'm **[FOUNDER NAME]**, and I'm building GapShield.
>
> GapShield is fixed-price, fully collateralized downside protection for tokenized equities.
>
> Tokenized stocks can remain transferable around the clock, but the markets that price the underlying equities still close. If meaningful news breaks while that market is shut, the stock can reopen far below its previous close, and a stop-loss cannot protect an investor through that gap.
>
> GapShield lets a holder pay a known stablecoin premium to protect a defined amount of exposure. Underwriters provide USDG liquidity, and the protocol fully reserves the maximum liability before protection is issued.
>
> Our first wedge is the Friday-close to Monday-open downside gap. We've already deployed the protocol on testnet and completed a full on-chain lifecycle from liquidity deposit and policy purchase through settlement and payout.
>
> The bigger opportunity is a parametric risk layer for tokenized real-world assets — covering weekend gaps, earnings, holidays and other bounded event-driven risks.
>
> I'm building GapShield because I believe bringing assets on-chain also requires bringing their risk-management infrastructure on-chain.
>
> That's GapShield: protect the gap, keep the exposure.

### Pitch video URL

**TBD.**

---

## 16. Founder profile fields

Fill these with the identity of the founder/account actually making this submission. Do not reuse another person's details or imply another person built the project.

- Full name: **TBD**
- Role: **Founder & Builder**
- Age: **TBD**
- Gender: **TBD**
- Country: **TBD**
- City: **TBD**
- Currently in school?: **TBD**
- Telegram: **TBD**
- X: **TBD**
- LinkedIn: **TBD**
- GitHub profile: **TBD**
- Other relevant link: **TBD**

### Educational background — draft structure

> I have a background in **[education]**, which trained me in evidence-based problem solving and structured analysis. Alongside this, I've developed experience in software development, data analysis, product design and digital products through independent projects and hackathons.

Only keep skills that are true for the submitting founder.

### Where have you worked or built before? — draft structure

> I currently work in **[role/domain]** while independently building software products. I've built projects across **[relevant areas]**, often handling product research, implementation, testing, deployment and presentation end to end. My experience in **[relevant domain]** is directly useful to GapShield because **[founder-market-fit explanation]**.

---

## 17. Final survey guidance

Answer all survey questions truthfully.

### What most motivated you to enter?

Recommended only if accurate:

- Build or launch a product
- Colosseum investment
- Feedback and exposure

### Groups that supported you

Select only groups that genuinely supported the project. Leave blank if none.

### Previous ecosystem experience

Do not claim prior Solana shipping experience based on GapShield unless GapShield actually gains a Solana integration. Answer based on the submitting founder's real experience.

### Likelihood of continuing the project

**Very likely / Yes**, if that remains the plan.

### What would help you take the next step?

Strong GapShield answers:

- Users and distribution
- Feedback and mentorship
- Fundraising

---

## 18. Current limitations

- Robinhood Chain Testnet only in the current deployed version.
- No Solana integration yet.
- Trusted demo oracle.
- Operator-gated settlement.
- One asset (TSLA).
- One prototype pricing tier.
- One active epoch.
- No production frontend yet.
- Contracts are unaudited.
- No production users or revenue.
- Blockscout source verification is unavailable for the deployed compiler version; bytecode matching is documented instead.

---

## 19. Roadmap

1. Add a production-grade reference-price adapter with freshness and market-session validation.
2. Add a buyer/underwriter interface for quotes, coverage, solvency and claims.
3. Expand to multiple tokenized equities and protection tiers.
4. Calibrate pricing using historical event and gap data.
5. Add holiday and earnings protection products.
6. Audit the contracts and strengthen administration with multisig/timelock controls before production use.
7. Pursue embedded distribution through wallets, tokenized-equity venues and other RWA platforms.
8. If targeting a Solana-native competition, build and validate a genuine Solana deployment/integration before claiming Solana support.

---

## 20. Final pre-submit checklist

- [ ] Project name is GapShield everywhere.
- [x] Final website/live product URL added: https://web-nu-three-12.vercel.app
- [ ] GitHub repository is accessible to judges.
- [ ] If private, `hackathon@colosseum.com` has access.
- [ ] Project graphic/logo uploaded.
- [ ] Demo video is public or unlisted and playable.
- [ ] Demo video is within the form's time limit.
- [ ] Pitch video is public or unlisted and playable.
- [ ] Pitch video is within the form's time limit.
- [ ] Founder identity fields match the actual submitting founder.
- [ ] Telegram, X, LinkedIn and GitHub links are correct.
- [ ] Chain selection matches actual integrations.
- [ ] No Solana integration is claimed unless one exists.
- [ ] Category is RWA, with DeFi as secondary if allowed.
- [ ] Pre-existing work is disclosed.
- [ ] Pre-Colosseum baseline commit `8b262b7` is preserved.
- [ ] Access instructions match the actual live product.
- [ ] No claim exceeds what the repository or deployment proves.
- [ ] README is current.
- [ ] Main branch is clean.
- [ ] Tests pass.
- [ ] Final submission preview checked before clicking Submit.

---

## 21. Final positioning

GapShield is not trying to recreate an options exchange.

It starts with a narrow, recurring market discontinuity that is easy to explain and objectively settle. The larger thesis is that tokenized real-world assets will need native risk-management infrastructure alongside trading, custody and settlement.

**GapShield: Protect the gap. Keep the exposure.**
