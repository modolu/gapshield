# GapShield — Final Submission Checklist

Deadline shown on HackQuest: **`Oct 4,2026 15:59`**. The timezone isn't stated, so submit early (aim for 24h+
of margin). Status as of 2026-10-03.

| # | Item | Status | Notes |
|---|---|---|---|
| 1 | Repo public | ✅ | https://github.com/modolu/gapshield (visibility: PUBLIC) |
| 2 | CI green | ✅ | Run `37146441151` passed (hygiene, contracts, web). Re-check after the submission-docs commit. |
| 3 | Contracts deployed | ✅ | Robinhood Chain Testnet 46630; `deployments/46630.json` |
| 4 | Evidence committed | ✅ | `docs/TESTNET_DEMO_EVIDENCE.md` (commit `2feb3a6`) |
| 5 | Contract addresses in README / SUBMISSION / form copy | ✅ | Included in the submission-prep files. |
| 6 | Source verification | ⚠️ | Blockscout lacks solc 0.8.37, so source verification isn't possible there yet. Bytecode match is documented in the evidence file. |
| 7 | README, LICENSE, SUBMISSION.md, form copy | ✅ | Included in the submission-prep files. |
| 8 | Demo video recorded | ⬜ | Follow `docs/DEMO_VIDEO_PLAN.md` (2:30–2:50) |
| 9 | Demo video uploaded (public or unlisted link) | ⬜ | YouTube, Loom, etc. Test the link in a private window. |
| 10 | Screenshots | ⬜ | Suggested: README top; explorer claim tx showing the 40 USDG transfer; terminal `getEpochState(2)` output; evidence-doc tx table |
| 11 | HackQuest registration | ✅ | Registration completed before the deadline. |
| 12 | HackQuest form filled | ⬜ | Paste from `docs/SUBMISSION_COPY.md` |
| 13 | GitHub URL in form | ⬜ | https://github.com/modolu/gapshield |
| 14 | No secrets in repo | ✅ | `.env`, keystores, `cache/` are gitignored. Committed docs and scripts scanned. `broadcast/` not committed. |
| 15 | Links tested | ✅ | Explorer tx/address pages, GitHub, Paxos docs return 200 (faucet rate-limits automated checks) |
| 16 | Oracle disclaimer present everywhere | ✅ | README, SUBMISSION.md, form copy, evidence, runbook |
| 17 | Final submit button pressed | ⬜ | |
| 18 | Screenshot of the submission confirmation saved | ⬜ | |

## Last-minute sanity checks (2 minutes)

```sh
gh run list --repo modolu/gapshield --limit 1   # latest CI is success
cast call 0xA1De944d3d1247747a020AB7C325431D9221B13d "totalAssets()(uint256)" --rpc-url https://rpc.testnet.chain.robinhood.com   # 967040000
```

Before you submit, make sure nothing claims users, audits, production readiness or a decentralized oracle.
