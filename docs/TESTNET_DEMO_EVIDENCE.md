# GapShield — Robinhood Chain Testnet Demo Evidence

> **TESTNET DEMO ORACLE.** This demo was settled with `SnapshotOracle`. A single trusted operator (the deployer)
> posted the reference prices. No market data source verified them. That is intentional for the hackathon demo.
> **This is not production settlement and is not production-safe.** The oracle labels itself on-chain:
> `ORACLE_KIND()` returns `"TESTNET DEMO ORACLE"`.

Recorded 2026-10-03. Every value below was read back from the chain after the transactions confirmed, and all
transactions have receipt status `1`.

## Network and contracts

| Item | Value |
|---|---|
| Network | Robinhood Chain Testnet |
| Chain ID | `46630` |
| RPC | `https://rpc.testnet.chain.robinhood.com` |
| Explorer | `https://explorer.testnet.chain.robinhood.com` |
| ProtectionPool | `0xA1De944d3d1247747a020AB7C325431D9221B13d` |
| ProtectionReceipt | `0x19573Ed5eee1D348626679737844E769527C1c46` |
| SnapshotOracle (TESTNET DEMO ORACLE) | `0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6` |
| USDG (official Paxos, 6 decimals) | `0x7E955252E15c84f5768B83c41a71F9eba181802F` |
| Owner / settlement operator / oracle owner / LP / buyer | `0xa1a35d50BF93274F844EE7Acee00fFe7D64da1ED` |
| TSLA assetId | `0x0a8f1f385fed9c77a2e0daa363ccc865e971bdbe4458bb570cc0acb068d7c0f2` |
| TSLA feedId (Pyth Pro id 1435, exponent −5) | `0x000000000000000000000000000000000000000000000000000000000000059b` |

The addresses are also in `deployments/46630.json`. In this demo one wallet plays every role (LP, buyer, operator).

`deployments/46630.json` records Solidity `block.number` from the deployment script. On Arbitrum-based chains, Solidity
`block.number` reflects the first non-Arbitrum ancestor-chain block estimate rather than the L2 explorer height, so that
manifest value is not expected to match the Robinhood Testnet explorer block numbers listed below.

## Terms (frozen Phase 0 tier)

| Term | Value |
|---|---|
| Trigger | 5.00% (500 bps) |
| Max cover | 5.00% (500 bps) |
| Premium | 0.80% (80 bps), rounded up |
| Protocol fee | 12% of premium (1200 bps); 88% goes to LPs |
| Notional | whole USDG, 10 – 10,000 |
| Utilization cap | 50% |

## Transactions

### Setup

| Step | Tx hash | Block |
|---|---|---|
| Deploy SnapshotOracle | `0x16e9584487643d843441533aaa76c3132df7956d55a2f630ac786cf6ce5d7505` | 128255328 |
| Deploy ProtectionPool (+ ProtectionReceipt) | `0xe85cc4aaf4dee752d359d7d0aee4fa3773212662e44c3df140a26fe05e47ee48` | 128255354 |
| `addAsset(TSLA)` | `0xf6c6e664d513e0210227afd728b8a79561af4d2b3f822ef0cf8a5667033be4ce` | 128255360 |
| `setSettlementOperator` | `0x165521ea7270fb4da418daacc12315b5a8057df8e56d5aac16f0fe06f23f5e30` | 128255377 |
| Approve 1,000 USDG to pool | `0xbac9dfd26dfe88b43f4be8e1926b70d9d46d1d6b83a7f0a06c27f891680be942` | 128256600 |
| LP `deposit` 1,000 USDG | `0x6ee94fa32f1d9068540dad97ff5739c37610687b41d0a0605189a2886dafca0e` | 128256821 |

### Epoch 1 — no settlement, voided after the deadline (oracle-failure path)

Epoch 1 opened, but the purchase attempt arrived after its sale cutoff and reverted with `SaleClosed(1)`, so no
policies were sold. No settlement was submitted. Once `settlementDeadline` (`1791049688`) had passed, `voidEpoch(1)`
moved it to `Voided`, and a new epoch could then open.

| Step | Tx hash | Block |
|---|---|---|
| `createEpoch` (epoch 1) | `0x73679f5c4f1d90676521c2ba1e6edf33a7d99aceb323430191bea80521604265` | 128257556 |
| Approve 8 USDG premium (later used for policy 1) | `0x95925db690755322cc8216c3a3cdbbbfd7dad3bd70869a44e0507fb6c72a78d7` | 128258187 |
| `voidEpoch(1)`: `EpochVoided(1, released 0, refundable 0)` | `0xbb0c86bdd301e86d7e326dce03675c0ca8c6ca40fb5a4ce3cbd23d8016815a03` | 128284543 |

### Epoch 2 — full successful protection lifecycle

Epoch 2 timeline (unix seconds): sale cutoff `1791051803`; close window `[1791051803, 1791052403)`; open window
`[1791052523, 1791053123)`; settlement deadline `1791054923`.

| Step | Tx hash | Block |
|---|---|---|
| `createEpoch` (epoch 2) | `0x9c54503f07398d11039a58a89f508fdb3763a63de0a5cba436178299965f6605` | 128284556 |
| `buyProtection(2, 1000000000)` → policy 1 | `0xc981a8e030d3e5f7693d84d0a2302a9ad8e5d4c5cde1afec3260542972c8c22b` | 128284565 |
| `postSnapshot(feed, 10000000, 1791051863)`: close 100.00000 | `0x224c3cb498002b4594d76f905a77fdacb09bf3cad0941a58a7f50b48bc8a8e74` | 128296295 |
| `settleClose(2, snapshotId)` | `0xb5b3b60f8ee80a8e4a0c788bfe01333b0d124928088883b78388870771a70eac` | 128296305 |
| `postSnapshot(feed, 9100000, 1791052583)`: open 91.00000 | `0xec8a140cca9429bf675a39dac00f291253ce6ab1e08e3682ab951200df3b9d21` | 128296324 |
| `settleOpen(2, snapshotId)`: epoch Settled | `0x0b5f6ec5b38270c41aadfa0f0c4fc69536117072a4aaf1b2ae0972bbb18a6021` | 128296342 |
| `claim(1)`: 40 USDG paid | `0x3f30b8dd781cbbd176d6a4d27b54c006522aeda0cfc1373c39e958d9832437b4` | 128296363 |

The purchase was made before the sale cutoff (block timestamp `1791051303` < `1791051803`). Both reference times fall
inside their half-open windows and were not in the future when posted. The close snapshot was posted at
`1791053627`, after its window had ended. The contract allows this, because the reference time, not the posting time,
must fall in the window. Everything settled before the deadline.

## Scenario: 100.00000 → 91.00000

| Quantity | Value |
|---|---|
| Epoch / policy | epoch **2**, policy **1** |
| Notional | 1,000 USDG (`1000000000`) |
| Premium | **8 USDG** (`8000000`) |
| Max payout reserved at purchase | 50 USDG (`50000000`) |
| Close reference | `10000000` (100.00000) at `1791051863` |
| Open reference | `9100000` (91.00000) at `1791052583` |
| Raw downside gap | **9%** (`gapBps = 900`) |
| Trigger | 5% |
| Covered gap | **4%** (`coveredBps = 400`) |
| Payout (`actualOwed`) | **40 USDG** (`40000000`) |
| Protocol fee | **0.96 USDG** (`960000`) |
| LP premium share | **7.04 USDG** (`7040000`) |

`EpochSettled(2, gapBps 900, coveredBps 400, actualOwed 40000000, protocolFee 960000, lpPremium 7040000)` was emitted
in the `settleOpen` transaction. `ProtectionClaimed(1, 2, owner, 40000000)` was emitted in the claim.

## Accounting, read back from the chain

| Value | Before purchase | After purchase | After settlement | After claim (final) |
|---|---:|---:|---:|---:|
| `totalAssets` (LP-owned) | 1,000 | 1,000 | 967.04 | **967.04** |
| `reservedLiability` | 0 | 50 | 0 | **0** |
| `pendingPremium` | 0 | 8 | 0 | **0** |
| `claimablePayouts` | 0 | 0 | 40 | **0** |
| `protocolFeesAccrued` | 0 | 0 | 0.96 | **0.96** |
| Pool USDG balance | 1,000 | 1,008 | 1,008 | **968** |
| Deployer USDG balance | 100 | 92 | 92 | **132** |

All figures are in USDG. Final LP assets: 1,000 − 40 payout + 7.04 LP premium = **967.04 USDG**.

Final reconciliation (base units): pool balance `968000000` = `totalAssets 967040000` + `claimablePayouts 0` +
`protocolFeesAccrued 960000` + `pendingPremium 0`. That's exact, with no unaccounted tokens.

Final epoch 2 state: `Settled`; `soldNotional 1000000000`, `soldLiability 50000000`, `premiumCollected 8000000`,
close/open evidence hashes `0x4c8c45d3…a4c6` / `0x4a803c08…dc8a`. Policy 1: `claimed = true`; the receipt is still owned
by the buyer (it's non-transferable). Deployer USDG went 100 → 92 → 132 (−8 premium, +40 payout).

## Source verification

Blockscout source verification was attempted, and it returned `Fail - Unable to verify`. The explorer's supported
compilers stop at solc 0.8.36, and these contracts use 0.8.37. Instead, the deployed bytecode was compared with a local
build of this repository (contract sources unchanged since commit `af755c9`):

| Contract | Result |
|---|---|
| SnapshotOracle | Runtime bytecode identical, byte for byte |
| ProtectionPool | Identical except its 384 bytes of immutables, which hold the expected values: USDG address, receipt address, utilization cap `5000` and USDG decimals `6` |
| ProtectionReceipt | Identical except its 64 bytes of immutables, which hold the pool address |

To check this yourself:

```sh
forge build
cast code 0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6 --rpc-url https://rpc.testnet.chain.robinhood.com
forge inspect contracts/oracles/SnapshotOracle.sol:SnapshotOracle deployedBytecode   # identical output
```

For the pool and the receipt, mask the ranges listed in `deployedBytecode.immutableReferences` in
`out/<Contract>.sol/<Contract>.json` before comparing.

## Reproduce

`script/RunTestnetDemo.s.sol` drives the lifecycle against the deployed contracts. It checks chain state before every
transaction, so re-running a phase never repeats one.

```sh
export POOL=0xA1De944d3d1247747a020AB7C325431D9221B13d ORACLE=0xA288DC9B900DA2a6Df20A129C3539473fcAF5ac6
# void an expired epoch if needed, open a demo epoch, buy 1,000 USDG of cover
DEMO_PHASE=start DEMO_SALE_MINUTES=20 DEMO_WINDOW_MINUTES=10 DEMO_GAP_MINUTES=2 DEMO_DEADLINE_MINUTES=30 \
  forge script script/RunTestnetDemo.s.sol --rpc-url https://rpc.testnet.chain.robinhood.com \
  --account gapshield-deployer --sender <deployer> --broadcast --slow
# after the open-window reference time: close + open snapshots, settle, claim
DEMO_PHASE=settle DEMO_POLICY_ID=<policyId> forge script script/RunTestnetDemo.s.sol \
  --rpc-url https://rpc.testnet.chain.robinhood.com --account gapshield-deployer --sender <deployer> --broadcast --slow
```

Before broadcasting, the flow was rehearsed on a local fork of the live chain, and it produced the same final values.
