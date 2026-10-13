const evidenceUrl = "https://github.com/modolu/gapshield/blob/main/docs/TESTNET_DEMO_EVIDENCE.md";
const repoUrl = "https://github.com/modolu/gapshield";
const explorerUrl = "https://explorer.testnet.chain.robinhood.com/address/0xA1De944d3d1247747a020AB7C325431D9221B13d";

export default function Home() {
  return (
    <main className="min-h-screen bg-[#07110f] text-[#f3f6f4]">
      <section className="mx-auto max-w-6xl px-6 pb-16 pt-8 md:px-10 md:pb-24">
        <nav className="flex items-center justify-between border-b border-white/10 pb-5">
          <div className="flex items-center gap-3">
            <div className="grid h-9 w-9 place-items-center rounded-xl border border-emerald-300/30 bg-emerald-300/10 font-semibold text-emerald-200">G</div>
            <span className="font-semibold tracking-tight">GapShield</span>
          </div>
          <a href={repoUrl} target="_blank" rel="noreferrer" className="text-sm text-white/65 transition hover:text-white">GitHub ↗</a>
        </nav>

        <div className="grid gap-12 pt-16 md:grid-cols-[1.25fr_.75fr] md:items-center md:pt-24">
          <div>
            <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-emerald-300/20 bg-emerald-300/5 px-3 py-1 text-xs font-medium uppercase tracking-[0.18em] text-emerald-200">
              Live testnet prototype
            </div>
            <h1 className="max-w-4xl text-5xl font-semibold leading-[1.02] tracking-[-0.045em] md:text-7xl">
              Protect the gap. <span className="text-emerald-300">Keep the exposure.</span>
            </h1>
            <p className="mt-7 max-w-2xl text-lg leading-8 text-white/65 md:text-xl">
              Fixed-price, fully collateralized downside protection for tokenized equities. GapShield covers defined close-to-open downside gaps without forcing holders to exit their position.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <a href={evidenceUrl} target="_blank" rel="noreferrer" className="rounded-xl bg-emerald-300 px-5 py-3 text-sm font-semibold text-[#07110f] transition hover:bg-emerald-200">View live proof</a>
              <a href={explorerUrl} target="_blank" rel="noreferrer" className="rounded-xl border border-white/15 px-5 py-3 text-sm font-semibold text-white transition hover:border-white/30 hover:bg-white/5">View contract ↗</a>
            </div>
          </div>

          <div className="rounded-3xl border border-white/10 bg-white/[0.035] p-6 shadow-2xl shadow-black/30">
            <p className="text-xs uppercase tracking-[0.18em] text-white/40">Live demo outcome</p>
            <div className="mt-6 grid grid-cols-2 gap-4">
              <Metric label="Protected" value="1,000" unit="USDG" />
              <Metric label="Premium" value="8" unit="USDG" />
              <Metric label="Price gap" value="9%" unit="100 → 91" />
              <Metric label="Payout" value="40" unit="USDG" highlight />
            </div>
            <div className="mt-5 rounded-2xl border border-white/10 bg-black/20 p-4 text-sm leading-6 text-white/55">
              A 9% downside gap triggered 4% covered loss after the 5% threshold, producing a 40 USDG on-chain payout.
            </div>
          </div>
        </div>
      </section>

      <section className="border-y border-white/10 bg-white/[0.025]">
        <div className="mx-auto grid max-w-6xl gap-px px-6 py-12 md:grid-cols-3 md:px-10">
          <Step n="01" title="Underwrite" text="Liquidity providers deposit USDG into a fully collateralized ERC-4626 protection pool." />
          <Step n="02" title="Protect" text="A holder pays a fixed premium. Maximum liability is reserved immediately when protection is purchased." />
          <Step n="03" title="Settle" text="Reference close and open prices determine the payout. The receipt owner claims USDG directly on-chain." />
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-6 py-16 md:px-10 md:py-24">
        <div className="grid gap-10 md:grid-cols-2">
          <div>
            <p className="text-xs uppercase tracking-[0.18em] text-emerald-200">The wedge</p>
            <h2 className="mt-4 text-3xl font-semibold tracking-tight md:text-4xl">Weekend downside gaps in tokenized US equities.</h2>
          </div>
          <div className="space-y-5 text-base leading-7 text-white/60">
            <p>Tokenized stocks can remain transferable on-chain while the market that prices the underlying equity is closed. If material news lands during that window, Monday can reopen sharply lower.</p>
            <p>A stop-loss cannot fill through a discontinuous price gap. GapShield turns that narrow risk into a simple prepaid protection product with a known premium and known maximum payout.</p>
          </div>
        </div>

        <div className="mt-14 grid gap-4 md:grid-cols-4">
          <Proof title="Network" value="Robinhood Chain Testnet" />
          <Proof title="Settlement asset" value="Paxos USDG" />
          <Proof title="Tests" value="208 passing" />
          <Proof title="Status" value="Testnet / unaudited" />
        </div>

        <div className="mt-14 rounded-3xl border border-white/10 bg-gradient-to-br from-emerald-300/10 to-transparent p-7 md:p-10">
          <p className="text-xs uppercase tracking-[0.18em] text-emerald-200">Bigger vision</p>
          <h2 className="mt-4 max-w-3xl text-3xl font-semibold tracking-tight md:text-4xl">A parametric risk layer for tokenized real-world assets.</h2>
          <p className="mt-5 max-w-3xl text-base leading-7 text-white/60">Weekend gaps are the first wedge. The same model can extend to earnings, holidays and other objective, bounded event-driven risks as more real-world assets move on-chain.</p>
        </div>
      </section>

      <footer className="border-t border-white/10">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-8 text-sm text-white/40 md:flex-row md:items-center md:justify-between md:px-10">
          <p>GapShield · Protect the gap. Keep the exposure.</p>
          <div className="flex gap-5">
            <a className="hover:text-white" href={repoUrl} target="_blank" rel="noreferrer">GitHub</a>
            <a className="hover:text-white" href={evidenceUrl} target="_blank" rel="noreferrer">Demo evidence</a>
          </div>
        </div>
      </footer>
    </main>
  );
}

function Metric({ label, value, unit, highlight = false }: { label: string; value: string; unit: string; highlight?: boolean }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/20 p-4">
      <p className="text-xs text-white/40">{label}</p>
      <p className={`mt-2 text-2xl font-semibold ${highlight ? "text-emerald-300" : "text-white"}`}>{value}</p>
      <p className="mt-1 text-xs text-white/35">{unit}</p>
    </div>
  );
}

function Step({ n, title, text }: { n: string; title: string; text: string }) {
  return (
    <div className="p-6 md:px-8">
      <p className="font-mono text-xs text-emerald-200">{n}</p>
      <h3 className="mt-3 text-xl font-semibold">{title}</h3>
      <p className="mt-3 text-sm leading-6 text-white/55">{text}</p>
    </div>
  );
}

function Proof({ title, value }: { title: string; value: string }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-white/[0.025] p-5">
      <p className="text-xs text-white/40">{title}</p>
      <p className="mt-2 font-medium text-white/80">{value}</p>
    </div>
  );
}
