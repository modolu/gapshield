"use client";

import { useCallback, useEffect, useState } from "react";
import { createWalletClient, custom, type Address } from "viem";
import {
  CHAIN_ID, EXPLORER, POOL, RECEIPT, RPC_URL, USDG, erc20Abi, parseUsdg, pct,
  poolAbi, publicClient, receiptAbi, robinhoodTestnet, short, statusNames, usdg,
} from "@/lib/gapshield";

type Eip1193 = { request(args: { method: string; params?: unknown[] | object }): Promise<unknown> };
type EpochConfig = {
  saleCutoff: bigint; triggerBps: number; maxCoverBps: number; premiumBps: number; protocolFeeBps: number;
  minNotional: bigint; maxNotional: bigint; maxAggregateLiability: bigint;
};
type EpochState = {
  soldNotional: bigint; soldLiability: bigint; premiumCollected: bigint; closePrice: bigint; openPrice: bigint;
  gapBps: number; coveredBps: number; status: number;
};
type Policy = { epochId: bigint; notional: bigint; premiumUSDG: bigint; maxPayout: bigint; claimed: boolean };
type PoolState = {
  activeEpochId: bigint; totalAssets: bigint; freeCollateral: bigint; reservedLiability: bigint; pendingPremium: bigint;
  claimablePayouts: bigint; protocolFeesAccrued: bigint; utilizationCapBps: number; paused: boolean;
  config: EpochConfig | null; epoch: EpochState | null; poolBalance: bigint;
};

const initialPool: PoolState = {
  activeEpochId: 0n, totalAssets: 0n, freeCollateral: 0n, reservedLiability: 0n, pendingPremium: 0n,
  claimablePayouts: 0n, protocolFeesAccrued: 0n, utilizationCapBps: 0, paused: false, config: null, epoch: null, poolBalance: 0n,
};

const txDemo = {
  deposit: "0x6ee94fa32f1d9068540dad97ff5739c37610687b41d0a0605189a2886dafca0e",
  purchase: "0xc981a8e030d3e5f7693d84d0a2302a9ad8e5d4c5cde1afec3260542972c8c22b",
  settle: "0x0b5f6ec5b38270c41aadfa0f0c4fc69536117072a4aaf1b2ae0972bbb18a6021",
  claim: "0x3f30b8dd781cbbd176d6a4d27b54c006522aeda0cfc1373c39e958d9832437b4",
};

function Metric({ label, value, note }: { label: string; value: string; note?: string }) {
  return <div className="card"><div className="kicker">{label}</div><div className="metric">{value}</div>{note && <div className="muted mt-1 text-sm">{note}</div>}</div>;
}

function TxState({ message, hash }: { message: string; hash?: string }) {
  if (!message) return null;
  return <div className="status-box" role="status">{message}{hash && <> · <a className="link" href={`${EXPLORER}/tx/${hash}`} target="_blank">View transaction ↗</a></>}</div>;
}

export default function GapShieldApp() {
  const [pool, setPool] = useState<PoolState>(initialPool);
  const [loadingPool, setLoadingPool] = useState(true);
  const [poolError, setPoolError] = useState("");
  const [account, setAccount] = useState<Address | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [walletBusy, setWalletBusy] = useState(false);
  const [notional, setNotional] = useState("1000");
  const [quote, setQuote] = useState<[bigint, bigint] | null>(null);
  const [protectTx, setProtectTx] = useState({ message: "", hash: "" });
  const [depositAmount, setDepositAmount] = useState("100");
  const [depositTx, setDepositTx] = useState({ message: "", hash: "" });
  const [policyId, setPolicyId] = useState("1");
  const [policy, setPolicy] = useState<Policy | null>(null);
  const [policyEpoch, setPolicyEpoch] = useState<EpochState | null>(null);
  const [policyOwner, setPolicyOwner] = useState<Address | null>(null);
  const [policyPayout, setPolicyPayout] = useState<bigint>(0n);
  const [policyLoading, setPolicyLoading] = useState(false);
  const [policyError, setPolicyError] = useState("");
  const [claimTx, setClaimTx] = useState({ message: "", hash: "" });

  const eth = typeof window !== "undefined" ? (window as typeof window & { ethereum?: Eip1193 }).ethereum : undefined;
  const onRightChain = chainId === CHAIN_ID;

  const refreshPool = useCallback(async () => {
    setLoadingPool(true); setPoolError("");
    try {
      const [activeEpochId, totalAssets, freeCollateral, reservedLiability, pendingPremium, claimablePayouts, protocolFeesAccrued, utilizationCapBps, paused, poolBalance] = await Promise.all([
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "activeEpochId" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "totalAssets" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "freeCollateral" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "reservedLiability" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "pendingPremium" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "claimablePayouts" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "protocolFeesAccrued" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "utilizationCapBps" }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "paused" }),
        publicClient.readContract({ address: USDG, abi: erc20Abi, functionName: "balanceOf", args: [POOL] }),
      ]);
      let config: EpochConfig | null = null; let epoch: EpochState | null = null;
      if (activeEpochId > 0n) {
        const [c, s] = await Promise.all([
          publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "getEpochConfig", args: [activeEpochId] }),
          publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "getEpochState", args: [activeEpochId] }),
        ]);
        config = c as unknown as EpochConfig; epoch = s as unknown as EpochState;
      }
      setPool({ activeEpochId, totalAssets, freeCollateral, reservedLiability, pendingPremium, claimablePayouts, protocolFeesAccrued, utilizationCapBps: Number(utilizationCapBps), paused, config, epoch, poolBalance });
    } catch (e) { setPoolError(e instanceof Error ? e.message : "Could not read live pool state."); }
    finally { setLoadingPool(false); }
  }, []);

  useEffect(() => { const timer = window.setTimeout(() => void refreshPool(), 0); return () => window.clearTimeout(timer); }, [refreshPool]);

  useEffect(() => {
    const timer = window.setTimeout(async () => {
      if (!pool.activeEpochId || !notional || Number(notional) <= 0) { setQuote(null); return; }
      try {
        const q = await publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "quote", args: [pool.activeEpochId, parseUsdg(notional)] });
        setQuote(q as [bigint, bigint]);
      } catch { setQuote(null); }
    }, 200);
    return () => window.clearTimeout(timer);
  }, [notional, pool.activeEpochId]);

  async function connectWallet() {
    if (!eth) { window.open("https://metamask.io/download/", "_blank"); return; }
    setWalletBusy(true);
    try {
      const accounts = await eth.request({ method: "eth_requestAccounts" }) as Address[];
      const id = await eth.request({ method: "eth_chainId" }) as string;
      setAccount(accounts[0] ?? null); setChainId(Number.parseInt(id, 16));
    } finally { setWalletBusy(false); }
  }

  async function switchNetwork() {
    if (!eth) return;
    try { await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: `0x${CHAIN_ID.toString(16)}` }] }); }
    catch {
      await eth.request({ method: "wallet_addEthereumChain", params: [{ chainId: `0x${CHAIN_ID.toString(16)}`, chainName: "Robinhood Chain Testnet", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: [RPC_URL], blockExplorerUrls: [EXPLORER] }] });
    }
    setChainId(CHAIN_ID);
  }

  async function walletClient() {
    if (!eth || !account) throw new Error("Connect your wallet first.");
    return createWalletClient({ account, chain: robinhoodTestnet, transport: custom(eth) });
  }

  async function ensureAllowance(amount: bigint, setState: (v: { message: string; hash: string }) => void) {
    if (!account) throw new Error("Connect your wallet first.");
    const allowance = await publicClient.readContract({ address: USDG, abi: erc20Abi, functionName: "allowance", args: [account, POOL] });
    if (allowance >= amount) return;
    const wc = await walletClient(); setState({ message: "Approve USDG in your wallet…", hash: "" });
    const hash = await wc.writeContract({ address: USDG, abi: erc20Abi, functionName: "approve", args: [POOL, amount] });
    setState({ message: "USDG approval submitted. Waiting for confirmation…", hash });
    await publicClient.waitForTransactionReceipt({ hash });
  }

  async function buyProtection() {
    if (!account || !onRightChain || !pool.config || !pool.epoch) return;
    const amount = parseUsdg(notional);
    try {
      setProtectTx({ message: "Checking USDG allowance…", hash: "" });
      await ensureAllowance(quote?.[0] ?? 0n, setProtectTx);
      const wc = await walletClient(); setProtectTx({ message: "Confirm protection purchase in your wallet…", hash: "" });
      const hash = await wc.writeContract({ address: POOL, abi: poolAbi, functionName: "buyProtection", args: [pool.activeEpochId, amount] });
      setProtectTx({ message: "Protection purchase submitted. Waiting for confirmation…", hash });
      await publicClient.waitForTransactionReceipt({ hash });
      setProtectTx({ message: "Protection purchased on-chain.", hash }); await refreshPool();
    } catch (e) { setProtectTx({ message: e instanceof Error ? e.message : "Purchase failed.", hash: "" }); }
  }

  async function deposit() {
    if (!account || !onRightChain) return;
    const amount = parseUsdg(depositAmount);
    try {
      setDepositTx({ message: "Checking USDG allowance…", hash: "" });
      await ensureAllowance(amount, setDepositTx);
      const wc = await walletClient(); setDepositTx({ message: "Confirm LP deposit in your wallet…", hash: "" });
      const hash = await wc.writeContract({ address: POOL, abi: poolAbi, functionName: "deposit", args: [amount, account] });
      setDepositTx({ message: "Deposit submitted. Waiting for confirmation…", hash });
      await publicClient.waitForTransactionReceipt({ hash });
      setDepositTx({ message: "USDG deposited into the underwriting pool.", hash }); await refreshPool();
    } catch (e) { setDepositTx({ message: e instanceof Error ? e.message : "Deposit failed.", hash: "" }); }
  }

  const loadPolicy = useCallback(async () => {
    const id = BigInt(policyId || "0"); if (id <= 0n) return;
    setPolicyLoading(true); setPolicyError(""); setPolicy(null);
    try {
      const p = await publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "getPolicy", args: [id] }) as unknown as Policy;
      if (p.epochId === 0n) throw new Error("Policy does not exist.");
      const [s, owner, payout] = await Promise.all([
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "getEpochState", args: [p.epochId] }),
        publicClient.readContract({ address: RECEIPT, abi: receiptAbi, functionName: "ownerOf", args: [id] }),
        publicClient.readContract({ address: POOL, abi: poolAbi, functionName: "previewPayout", args: [id] }),
      ]);
      setPolicy(p); setPolicyEpoch(s as unknown as EpochState); setPolicyOwner(owner); setPolicyPayout(payout);
    } catch (e) { setPolicyError(e instanceof Error ? e.message : "Could not load policy."); }
    finally { setPolicyLoading(false); }
  }, [policyId]);

  useEffect(() => { const timer = window.setTimeout(() => void loadPolicy(), 0); return () => window.clearTimeout(timer); }, [loadPolicy]);

  async function claim() {
    if (!account || !onRightChain || !policy) return;
    try {
      const wc = await walletClient(); setClaimTx({ message: "Confirm claim in your wallet…", hash: "" });
      const hash = await wc.writeContract({ address: POOL, abi: poolAbi, functionName: "claim", args: [BigInt(policyId)] });
      setClaimTx({ message: "Claim submitted. Waiting for confirmation…", hash });
      await publicClient.waitForTransactionReceipt({ hash }); setClaimTx({ message: "Claim finalized on-chain.", hash }); await loadPolicy(); await refreshPool();
    } catch (e) { setClaimTx({ message: e instanceof Error ? e.message : "Claim failed.", hash: "" }); }
  }

  const saleOpen = !!pool.config && !!pool.epoch && pool.epoch.status === 1 && !pool.paused;
  const utilization = pool.totalAssets > 0n ? Number(pool.reservedLiability * 10000n / pool.totalAssets) / 100 : 0;
  const policyStatus = policyEpoch ? statusNames[policyEpoch.status] ?? "Unknown" : "—";
  const canClaim = !!policy && !!policyEpoch && !policy.claimed && (policyEpoch.status === 3 || policyEpoch.status === 4) && !!account && policyOwner?.toLowerCase() === account.toLowerCase();

  return <main>
    <header className="sticky top-0 z-20 border-b border-white/10 bg-[#090d0f]/90 backdrop-blur">
      <div className="shell flex h-16 items-center justify-between gap-3">
        <a href="#top" className="font-semibold tracking-tight">GapShield</a>
        <nav className="hidden gap-5 text-sm text-zinc-400 md:flex"><a href="#protect">Protect</a><a href="#underwrite">Underwrite</a><a href="#policy">Policy</a><a href="#proof">Proof</a></nav>
        <div className="flex items-center gap-2">
          {account && !onRightChain && <button className="btn secondary" onClick={switchNetwork}>Switch network</button>}
          <button className="btn" onClick={connectWallet} disabled={walletBusy}>{account ? short(account) : eth ? "Connect wallet" : "Get wallet"}</button>
        </div>
      </div>
    </header>

    <section id="top" className="shell hero">
      <div className="pill">LIVE TESTNET PROTOTYPE · ROBINHOOD CHAIN · PAXOS USDG</div>
      <h1>Protect the gap.<br/><span>Keep the exposure.</span></h1>
      <p className="lead">Fixed-price, fully collateralized downside protection for tokenized equities. Pay a known premium before the market closes; claim USDG if the reopening gap crosses the defined trigger.</p>
      <div className="flex flex-wrap gap-3"><a className="btn" href="#protect">Open app</a><a className="btn secondary" href="https://github.com/modolu/gapshield" target="_blank">GitHub ↗</a><a className="btn secondary" href={`${EXPLORER}/address/${POOL}`} target="_blank">Live contract ↗</a></div>
      <div className="mt-10 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="LP assets" value={loadingPool ? "…" : `${usdg(pool.totalAssets)} USDG`} note="LP-owned capital" />
        <Metric label="Free collateral" value={loadingPool ? "…" : `${usdg(pool.freeCollateral)} USDG`} note="Available outside reserves" />
        <Metric label="Reserved liability" value={loadingPool ? "…" : `${usdg(pool.reservedLiability)} USDG`} note={`${utilization.toFixed(2)}% of LP assets`} />
        <Metric label="Protocol status" value={pool.epoch ? statusNames[pool.epoch.status] : "—"} note={`Epoch ${pool.activeEpochId.toString()}`} />
      </div>
      {poolError && <div className="status-box error mt-3">Live RPC read failed: {poolError}</div>}
    </section>

    <section id="protect" className="section shell grid gap-8 lg:grid-cols-[1.1fr_.9fr]">
      <div><div className="eyebrow">01 · BUY PROTECTION</div><h2>Know the cost before you sign.</h2><p className="copy">The current prototype protects the downside beyond a 5% gap, capped at the next 5%. Maximum liability is reserved the moment a policy is sold.</p>
        <div className="grid gap-3 sm:grid-cols-3 mt-6"><Metric label="Trigger" value={pool.config ? pct(pool.config.triggerBps) : "5.00%"}/><Metric label="Max cover" value={pool.config ? pct(pool.config.maxCoverBps) : "5.00%"}/><Metric label="Premium" value={pool.config ? pct(pool.config.premiumBps) : "0.80%"}/></div>
      </div>
      <div className="panel">
        <label htmlFor="notional">Protection notional (USDG)</label><input id="notional" inputMode="decimal" value={notional} onChange={e=>setNotional(e.target.value)} />
        <div className="quote-grid"><div><span>Premium</span><strong>{quote ? `${usdg(quote[0])} USDG` : "—"}</strong></div><div><span>Maximum payout</span><strong>{quote ? `${usdg(quote[1])} USDG` : "—"}</strong></div></div>
        {!saleOpen && <div className="notice">The current epoch is <strong>{pool.epoch ? statusNames[pool.epoch.status] : "unavailable"}</strong>, so new protection cannot be purchased right now. Live reads and historical proof remain available.</div>}
        {!account ? <button className="btn w-full" onClick={connectWallet}>Connect wallet to continue</button> : !onRightChain ? <button className="btn w-full" onClick={switchNetwork}>Switch to Robinhood Testnet</button> : <button className="btn w-full" disabled={!saleOpen || !quote} onClick={buyProtection}>Buy protection</button>}
        <TxState message={protectTx.message} hash={protectTx.hash}/>
      </div>
    </section>

    <section id="underwrite" className="section shell">
      <div className="eyebrow">02 · UNDERWRITE</div><div className="grid gap-8 lg:grid-cols-[.9fr_1.1fr]"><div><h2>Transparent, bounded underwriting.</h2><p className="copy">USDG collateral stays visibly separated across LP assets, reserved liability, premium escrow, claimable payouts and protocol fees.</p>
        <div className="panel mt-6"><label htmlFor="deposit">Deposit amount (USDG)</label><input id="deposit" inputMode="decimal" value={depositAmount} onChange={e=>setDepositAmount(e.target.value)} />
          {!account ? <button className="btn w-full" onClick={connectWallet}>Connect wallet</button> : !onRightChain ? <button className="btn w-full" onClick={switchNetwork}>Switch network</button> : <button className="btn w-full" disabled={pool.paused || Number(depositAmount)<=0} onClick={deposit}>Approve & deposit USDG</button>}
          <TxState message={depositTx.message} hash={depositTx.hash}/></div>
      </div><div className="grid gap-3 sm:grid-cols-2"><Metric label="LP-owned assets" value={`${usdg(pool.totalAssets)} USDG`}/><Metric label="Reserved liability" value={`${usdg(pool.reservedLiability)} USDG`}/><Metric label="Premium escrow" value={`${usdg(pool.pendingPremium)} USDG`}/><Metric label="Claimable payouts" value={`${usdg(pool.claimablePayouts)} USDG`}/><Metric label="Protocol fees" value={`${usdg(pool.protocolFeesAccrued)} USDG`}/><Metric label="Raw pool balance" value={`${usdg(pool.poolBalance)} USDG`}/></div></div>
    </section>

    <section id="policy" className="section shell grid gap-8 lg:grid-cols-[.8fr_1.2fr]">
      <div><div className="eyebrow">03 · POLICY & CLAIM</div><h2>Inspect settlement on-chain.</h2><p className="copy">Policy receipts are non-transferable ERC-721s. Enter a policy ID to inspect its owner, epoch, terms, settlement result and claim state.</p>
        <div className="panel mt-6"><label htmlFor="policy-id">Policy ID</label><div className="flex gap-2"><input id="policy-id" inputMode="numeric" value={policyId} onChange={e=>setPolicyId(e.target.value.replace(/\D/g,""))}/><button className="btn secondary" onClick={loadPolicy}>Load</button></div>{policyError && <div className="status-box error">{policyError}</div>}</div>
      </div>
      <div className="panel min-h-80">{policyLoading ? <div className="muted">Reading policy from chain…</div> : policy && policyEpoch ? <>
        <div className="flex flex-wrap items-center justify-between gap-3"><div><div className="kicker">POLICY #{policyId}</div><div className="text-xl font-semibold mt-1">{policyStatus}</div></div><span className="pill">{policy.claimed ? "CLAIMED" : "UNCLAIMED"}</span></div>
        <div className="policy-grid"><div><span>Owner</span><strong>{policyOwner ? short(policyOwner) : "—"}</strong></div><div><span>Notional</span><strong>{usdg(policy.notional)} USDG</strong></div><div><span>Premium</span><strong>{usdg(policy.premiumUSDG)} USDG</strong></div><div><span>Max payout</span><strong>{usdg(policy.maxPayout)} USDG</strong></div><div><span>Raw gap</span><strong>{pct(policyEpoch.gapBps)}</strong></div><div><span>Covered gap</span><strong>{pct(policyEpoch.coveredBps)}</strong></div><div><span>Settled payout</span><strong>{usdg(policyPayout)} USDG</strong></div><div><span>Epoch</span><strong>#{policy.epochId.toString()}</strong></div></div>
        {policy.claimed ? <div className="notice">This policy has already been finalized.</div> : policyEpoch.status < 3 ? <div className="notice">This epoch has not reached a claimable terminal state yet.</div> : policyOwner && account && policyOwner.toLowerCase() !== account.toLowerCase() ? <div className="notice">Connect the receipt owner wallet to claim this policy.</div> : <button className="btn w-full" disabled={!canClaim} onClick={claim}>{policyEpoch.status===4 ? `Refund ${usdg(policy.premiumUSDG)} USDG premium` : `Claim ${usdg(policyPayout)} USDG`}</button>}
        <TxState message={claimTx.message} hash={claimTx.hash}/>
      </> : <div className="muted">Enter a valid policy ID.</div>}</div>
    </section>

    <section id="proof" className="section shell">
      <div className="eyebrow">LIVE TESTNET PROOF</div><h2>A complete lifecycle already settled on-chain.</h2><p className="copy max-w-2xl">The historical demo used the deployed contracts and Paxos USDG. A trusted testnet operator posted the reference snapshots through the explicitly labelled TESTNET DEMO ORACLE.</p>
      <div className="timeline mt-8">
        {[["1","Underwrite","1,000 USDG deposited",txDemo.deposit],["2","Protect","1,000 USDG notional · 8 USDG premium",txDemo.purchase],["3","Settle","$100 → $91 · 9% gap · 4% covered",txDemo.settle],["4","Claim","40 USDG paid to the buyer",txDemo.claim]].map(([n,t,d,h])=><a key={n} href={`${EXPLORER}/tx/${h}`} target="_blank" className="proof-card"><span>{n}</span><div><strong>{t}</strong><p>{d}</p><small>View transaction ↗</small></div></a>)}
      </div>
    </section>

    <section className="section shell"><div className="panel border-cyan-400/20"><div className="eyebrow">SAFETY & SCOPE</div><h2 className="text-2xl">Built to prove the mechanism, not to hide the caveats.</h2><p className="copy">GapShield is testnet-only and unaudited. Settlement currently uses a trusted <strong className="text-white">TESTNET DEMO ORACLE</strong>; it is not a production market-data oracle. Pricing is fixed prototype pricing. No production-user, revenue, audit, or mainnet claims are made.</p></div></section>

    <footer className="border-t border-white/10"><div className="shell py-8 flex flex-col gap-3 text-sm text-zinc-500 sm:flex-row sm:justify-between"><span>GapShield · Protect the gap. Keep the exposure.</span><span><a className="link" href="https://github.com/modolu/gapshield" target="_blank">GitHub</a> · <a className="link" href={`${EXPLORER}/address/${POOL}`} target="_blank">Explorer</a></span></div></footer>
  </main>;
}
