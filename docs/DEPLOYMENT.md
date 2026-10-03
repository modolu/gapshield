# GapShield — Deployment Runbook (Robinhood Chain Testnet)

> **TESTNET ONLY.** Settlement uses `SnapshotOracle`, the **TESTNET DEMO ORACLE**: a single trusted operator
> posts prices. It is not a production oracle and must never back real-money settlement.

**Live deployment and demo:** Robinhood Chain Testnet addresses are in `deployments/46630.json`, and a full on-chain
lifecycle (void path plus a settled 40 USDG payout) is recorded in [`TESTNET_DEMO_EVIDENCE.md`](TESTNET_DEMO_EVIDENCE.md).
`script/RunTestnetDemo.s.sol` replays it against deployed contracts.

## What gets deployed

`script/DeployGapShield.s.sol` deploys, in one broadcast:

| Contract | Notes |
|---|---|
| `ProtectionPool` | ERC-4626 USDG pool, utilization cap 5000 bps. Deploys its own `ProtectionReceipt`. |
| `ProtectionReceipt` | Non-transferable ERC-721; address read from `pool.receipt()`. |
| `SnapshotOracle` | TESTNET DEMO ORACLE. `ORACLE_KIND()` returns `"TESTNET DEMO ORACLE"` on-chain. |

It then registers TSLA (`assetId = keccak256("TSLA")`, feed `bytes32(uint256(1435))`, 5 price decimals) and sets the
settlement operator. The broadcasting account owns the pool and the oracle.

| Chain | USDG |
|---|---|
| 46630 Robinhood Chain Testnet | Official Paxos USDG `0x7E955252E15c84f5768B83c41a71F9eba181802F`. The script checks it has code, `decimals() == 6` and `symbol() == "USDG"`. |
| 31337 local Anvil | `MockUSDG` (LOCAL TEST ONLY) |

Any other chain ID is rejected.

On a real broadcast the addresses are written to `deployments/<chainId>.json`. Commit that file for 46630.
`deployments/31337.json` is gitignored.

## Prerequisites (user actions)

1. **Re-verify USDG** at https://docs.paxos.com/guides/stablecoin/usdg/testnet. The address must still be
   `0x7E955252E15c84f5768B83c41a71F9eba181802F`.
2. **Deployer keystore** (no private keys in files or env):
   ```sh
   cast wallet import gapshield-deployer --interactive
   cast wallet address --account gapshield-deployer
   ```
3. **Test ETH** for the deployer from https://faucet.testnet.chain.robinhood.com. Deployment needs about 8.6M gas,
   roughly 0.0002 ETH at the observed 0.01 gwei base fee. Get extra for settlement and demo transactions.
4. **Test USDG** from https://faucet.paxos.com/ for an LP wallet and a buyer wallet.
5. `.env` (never committed) with `ROBINHOOD_TESTNET_RPC_URL`, `DEPLOYER_ACCOUNT` and `DEPLOYER_ADDRESS`.
   Optionally set `SETTLEMENT_OPERATOR`.

## Deploy

```sh
source .env
# 1. Dry run against a fork of the live testnet (no keys, no broadcast)
forge script script/DeployGapShield.s.sol --fork-url $ROBINHOOD_TESTNET_RPC_URL --sender $DEPLOYER_ADDRESS

# 2. Broadcast
forge script script/DeployGapShield.s.sol --rpc-url $ROBINHOOD_TESTNET_RPC_URL \
  --account $DEPLOYER_ACCOUNT --sender $DEPLOYER_ADDRESS --broadcast
```

## Verify on Blockscout

The explorer is Blockscout (`/api/v2` responds). Verification has not been tried on this chain yet, so expect to
adjust flags.

```sh
V="--chain 46630 --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api/"
POOL=$(jq -r .protectionPool deployments/46630.json); ORACLE=$(jq -r .snapshotOracle deployments/46630.json)
RECEIPT=$(jq -r .protectionReceipt deployments/46630.json); OWNER=$(jq -r .owner deployments/46630.json)
USDG=$(jq -r .usdg deployments/46630.json)

forge verify-contract $V $ORACLE contracts/oracles/SnapshotOracle.sol:SnapshotOracle \
  --constructor-args $(cast abi-encode "constructor(address)" $OWNER)
forge verify-contract $V $POOL contracts/ProtectionPool.sol:ProtectionPool \
  --constructor-args $(cast abi-encode "constructor(address,address,uint16)" $USDG $OWNER 5000)
forge verify-contract $V $RECEIPT contracts/ProtectionReceipt.sol:ProtectionReceipt \
  --constructor-args $(cast abi-encode "constructor(address)" $POOL)
```

Alternatively, add `--verify --verifier blockscout --verifier-url ...` to the broadcast command.

## Demo lifecycle (TESTNET DEMO epoch, minutes not weekends)

```sh
export ETH_RPC_URL=$ROBINHOOD_TESTNET_RPC_URL
J=deployments/46630.json; POOL=$(jq -r .protectionPool $J); ORACLE=$(jq -r .snapshotOracle $J)
USDG=$(jq -r .usdg $J); FEED=$(jq -r .tslaFeedId $J); A="--account $DEPLOYER_ACCOUNT"
```

1. **LP deposits** (from the LP wallet):
   ```sh
   cast send $USDG "approve(address,uint256)" $POOL <amount>
   cast send $POOL "deposit(uint256,address)" <amount> <lp>
   ```
2. **Open a demo epoch** (owner). Defaults: sales close in 10 min, 5-min windows, 30-min deadline.
   ```sh
   POOL=$POOL ORACLE=$ORACLE forge script script/CreateDemoEpoch.s.sol --rpc-url $ETH_RPC_URL $A --sender $DEPLOYER_ADDRESS --broadcast
   ```
3. **Buyer purchases** before the cutoff. Notional must be a whole USDG amount between 10 and 10,000:
   ```sh
   cast send $USDG "approve(address,uint256)" $POOL <premium>
   cast send $POOL "buyProtection(uint256,uint256)" <epochId> 1000000000
   ```
4. **Close reference.** Once the close window has started, post the TESTNET DEMO snapshot (owner) and settle it
   (operator). `refTime` must be inside `[closeWindowStart, closeWindowEnd)` and not in the future.
   ```sh
   cast send $ORACLE "postSnapshot(bytes32,uint256,uint64)" $FEED 10000000 <refTime> $A
   ID=$(cast call $ORACLE "snapshotId(bytes32,uint64)(bytes32)" $FEED <refTime>)
   cast send $POOL "settleClose(uint256,bytes)" <epochId> $(cast abi-encode "f(bytes32)" $ID) $A
   ```
5. **Open reference.** Same steps in the open window, using `settleOpen`. This finalizes the epoch.
   For example, open `9100000` (91.00000) gives a 40 USDG payout per 1,000 USDG notional.
6. **Claim** (buyer): `cast send $POOL "claim(uint256)" <policyId>`.
7. **Oracle-failure path:** do nothing until `settlementDeadline`. Then anyone can call
   `cast send $POOL "voidEpoch(uint256)" <epochId>`, and buyers `claim` to get a full premium refund.

This exact flow was run against a local Anvil chain with real transactions (MockUSDG, compressed demo epoch).
After settlement it showed 40 USDG claimable, 0.96 USDG protocol fee and 9,967.04 USDG LP assets. The buyer received
40 USDG, and claimable payouts returned to 0.

## Real-weekend epoch (optional)

Use the frozen W40 timestamps in `docs/PHASE0_DECISIONS.md` §8. With SnapshotOracle it is still a TESTNET DEMO
settlement. The Monday open (2026-10-05T13:30Z) falls after the HackQuest submission cutoff.
