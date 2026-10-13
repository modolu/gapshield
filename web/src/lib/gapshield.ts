import { createPublicClient, defineChain, formatUnits, http, parseUnits } from "viem";

export const CHAIN_ID = 46630;
export const RPC_URL = "https://rpc.testnet.chain.robinhood.com";
export const EXPLORER = "https://explorer.testnet.chain.robinhood.com";
export const POOL = "0xA1De944d3d1247747a020AB7C325431D9221B13d" as const;
export const RECEIPT = "0x19573Ed5eee1D348626679737844E769527C1c46" as const;
export const USDG = "0x7E955252E15c84f5768B83c41a71F9eba181802F" as const;

export const robinhoodTestnet = defineChain({
  id: CHAIN_ID,
  name: "Robinhood Chain Testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: "Robinhood Testnet Explorer", url: EXPLORER } },
  testnet: true,
});

export const publicClient = createPublicClient({ chain: robinhoodTestnet, transport: http(RPC_URL) });

export const poolAbi = [
  { type: "function", name: "activeEpochId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalAssets", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "freeCollateral", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "reservedLiability", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pendingPremium", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claimablePayouts", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "protocolFeesAccrued", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "utilizationCapBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "paused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "getEpochConfig", stateMutability: "view", inputs: [{ name: "epochId", type: "uint256" }], outputs: [{ type: "tuple", components: [
    { name: "assetId", type: "bytes32" }, { name: "oracle", type: "address" }, { name: "saleCutoff", type: "uint64" },
    { name: "closeWindowStart", type: "uint64" }, { name: "closeWindowEnd", type: "uint64" }, { name: "openWindowStart", type: "uint64" },
    { name: "openWindowEnd", type: "uint64" }, { name: "settlementDeadline", type: "uint64" }, { name: "triggerBps", type: "uint16" },
    { name: "maxCoverBps", type: "uint16" }, { name: "premiumBps", type: "uint16" }, { name: "protocolFeeBps", type: "uint16" },
    { name: "minNotional", type: "uint256" }, { name: "maxNotional", type: "uint256" }, { name: "maxAggregateLiability", type: "uint256" }
  ] }] },
  { type: "function", name: "getEpochState", stateMutability: "view", inputs: [{ name: "epochId", type: "uint256" }], outputs: [{ type: "tuple", components: [
    { name: "soldNotional", type: "uint256" }, { name: "soldLiability", type: "uint256" }, { name: "premiumCollected", type: "uint256" },
    { name: "closePrice", type: "uint256" }, { name: "openPrice", type: "uint256" }, { name: "closeTime", type: "uint64" }, { name: "openTime", type: "uint64" },
    { name: "gapBps", type: "uint16" }, { name: "coveredBps", type: "uint16" }, { name: "status", type: "uint8" },
    { name: "closeEvidence", type: "bytes32" }, { name: "openEvidence", type: "bytes32" }
  ] }] },
  { type: "function", name: "getPolicy", stateMutability: "view", inputs: [{ name: "policyId", type: "uint256" }], outputs: [{ type: "tuple", components: [
    { name: "epochId", type: "uint256" }, { name: "notional", type: "uint256" }, { name: "premiumUSDG", type: "uint256" },
    { name: "maxPayout", type: "uint256" }, { name: "claimed", type: "bool" }
  ] }] },
  { type: "function", name: "quote", stateMutability: "view", inputs: [{ name: "epochId", type: "uint256" }, { name: "notional", type: "uint256" }], outputs: [{ name: "premium", type: "uint256" }, { name: "maxPayout", type: "uint256" }] },
  { type: "function", name: "previewPayout", stateMutability: "view", inputs: [{ name: "policyId", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "buyProtection", stateMutability: "nonpayable", inputs: [{ name: "epochId", type: "uint256" }, { name: "notional", type: "uint256" }], outputs: [{ name: "policyId", type: "uint256" }] },
  { type: "function", name: "deposit", stateMutability: "nonpayable", inputs: [{ name: "assets", type: "uint256" }, { name: "receiver", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claim", stateMutability: "nonpayable", inputs: [{ name: "policyId", type: "uint256" }], outputs: [{ type: "uint256" }] },
] as const;

export const erc20Abi = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

export const receiptAbi = [
  { type: "function", name: "ownerOf", stateMutability: "view", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ type: "address" }] },
] as const;

export const statusNames = ["None", "Open", "Close recorded", "Settled", "Voided"] as const;
export const usdg = (v: bigint) => Number(formatUnits(v, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 });
export const parseUsdg = (v: string) => parseUnits(v || "0", 6);
export const pct = (bps: number | bigint) => `${(Number(bps) / 100).toFixed(2)}%`;
export const short = (v: string) => `${v.slice(0, 6)}…${v.slice(-4)}`;
