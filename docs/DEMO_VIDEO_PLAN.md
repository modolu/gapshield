# GapShield — Demo Video Plan (target 2:30–2:50)

GapShield has no product UI yet, so this video shows only what exists: the GitHub repo, the evidence document, the
Robinhood Chain Testnet explorer (Blockscout), and a terminal. Do not show or describe app screens.

## Prepare before recording

- **Browser tabs, in this order:**
  1. https://github.com/modolu/gapshield (README).
  2. `docs/TESTNET_DEMO_EVIDENCE.md` on GitHub.
  3. LP deposit tx: https://explorer.testnet.chain.robinhood.com/tx/0x6ee94fa32f1d9068540dad97ff5739c37610687b41d0a0605189a2886dafca0e
  4. Purchase tx: https://explorer.testnet.chain.robinhood.com/tx/0xc981a8e030d3e5f7693d84d0a2302a9ad8e5d4c5cde1afec3260542972c8c22b
  5. Claim tx: https://explorer.testnet.chain.robinhood.com/tx/0x3f30b8dd781cbbd176d6a4d27b54c006522aeda0cfc1373c39e958d9832437b4
  6. Pool address: https://explorer.testnet.chain.robinhood.com/address/0xA1De944d3d1247747a020AB7C325431D9221B13d
- **Terminal:** font size 18+, run from the repo root with Foundry on `PATH`, and with these set:
  ```sh
  export ETH_RPC_URL=https://rpc.testnet.chain.robinhood.com P=0xA1De944d3d1247747a020AB7C325431D9221B13d
  ```
- **Dry-run every command once** so nothing waits on the network during recording. The public RPC is rate-limited; if
  a call fails, retry it.
- **Optional:** run `forge test --match-contract LifecycleTest -vv` once beforehand, so the cached build makes it fast.

## Scenes

### 1. The problem — 0:00–0:20 (20s)
**Screen:** README on GitHub, scrolled to the top (title, tagline, the status box).
**Action:** slowly scroll to "The problem".
**Voice-over:**
> "Tokenized stocks trade on-chain around the clock, but the market that prices them closes every weekend. When bad
> news lands on a Saturday, Monday opens with a gap, and a stop-loss can't fill through it. GapShield is weekend gap
> protection: protect the gap, keep the exposure."

### 2. How it works — 0:20–0:45 (25s)
**Screen:** README, "How it works" and the live example line.
**Action:** highlight steps 1–4, then the example sentence.
**Voice-over:**
> "Underwriters deposit Paxos USDG into a fully collateralized pool. Before Friday's cutoff, a holder pays a fixed
> premium of 0.8 percent. If Monday opens more than 5 percent below Friday's close, the contract pays the excess, capped
> at another 5 percent. The worst-case payout is reserved the moment protection is sold, so the pool can always pay."

### 3. Live on Robinhood Chain — 0:45–0:55 (10s)
**Screen:** README, "Live deployment" table, then the pool address tab (tab 6).
**Action:** point at the chain ID 46630 and the four addresses, then switch to the pool's explorer page.
**Voice-over:**
> "This is deployed on Robinhood Chain Testnet, using the official Paxos USDG contract."

### 4. LP liquidity — 0:55–1:05 (10s)
**Screen:** LP deposit tx (tab 3), "Token transfers" section.
**Action:** point at the 1,000 USDG transfer into the pool.
**Voice-over:**
> "An underwriter deposited 1,000 USDG of liquidity."

### 5. Protection purchase — 1:05–1:25 (20s)
**Screen:** Purchase tx (tab 4), token transfers.
**Action:** point at the 8 USDG transfer to the pool, then the `GSHIELD` receipt mint.
**Voice-over:**
> "Before the cutoff, a holder bought protection on 1,000 USDG of TSLA exposure. The premium is 8 USDG, held in escrow.
> They receive a non-transferable receipt, and the pool reserves the 50 USDG worst case."

### 6. The 100 → 91 settlement — 1:25–1:55 (30s)
**Screen:** Terminal.
**Action:** run, and point at the values as they appear:
```sh
cast call $P "getEpochState(uint256)((uint256,uint256,uint256,uint256,uint256,uint64,uint64,uint16,uint16,uint8,bytes32,bytes32))" 2
```
Point out close `10000000` (100.00000), open `9100000` (91.00000), gap `900`, covered `400`, status `3` (Settled).
**Voice-over:**
> "Over the 'weekend', the stock fell from 100 to 91, a 9 percent gap. The operator recorded both reference prices
> on-chain. The pool checked the time windows and settled deterministically: 9 percent gap, minus the 5 percent
> trigger, is 4 percent covered. These references came from our testnet demo oracle, which is clearly labelled and not
> a production price feed."

### 7. The 40 USDG payout — 1:55–2:10 (15s)
**Screen:** Claim tx (tab 5), token transfers.
**Action:** point at 40 USDG from the pool to the holder.
**Voice-over:**
> "The holder called claim and received exactly 40 USDG: 4 percent of 1,000. No claim form, no adjuster, no options."

### 8. On-chain evidence — 2:10–2:30 (20s)
**Screen:** Terminal, then `TESTNET_DEMO_EVIDENCE.md` (tab 2).
**Action:** run:
```sh
for f in totalAssets claimablePayouts protocolFeesAccrued reservedLiability pendingPremium; do echo "$f $(cast call $P "$f()(uint256)")"; done
```
Then scroll the evidence doc's transaction table.
**Voice-over:**
> "After the claim, the books close exactly: LPs hold 967.04 USDG, which is 1,000 minus the 40 payout plus 88 percent
> of the premium. The protocol earned 96 cents, and nothing is left owed or reserved. Every transaction is in the
> repo, including an earlier epoch that was voided when no settlement arrived, with buyers fully refundable."

### 9. Pitch — 2:30–2:50 (20s)
**Screen:** README, "Safety model", then the repo top.
**Voice-over:**
> "GapShield is fully collateralized, uses USDG end to end, and is covered by 208 tests, including a stateful
> invariant suite for solvency. Next up are a Pyth Pro oracle and a mobile app. GapShield: protect the gap, keep the
> exposure."

## Do / don't

- **Do** say "testnet" and "demo oracle" out loud at least once (scene 6).
- **Don't** claim users, audits, production readiness, decentralized pricing, or a frontend.
- Blockscout shows the contracts as unverified (the explorer lacks solc 0.8.37), and it may label the claim argument
  `boxIndex` (a signature-database guess). Don't dwell on either; the evidence doc explains them.
