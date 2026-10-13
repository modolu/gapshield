import { NextRequest, NextResponse } from "next/server";

const UPSTREAM = "https://rpc.testnet.chain.robinhood.com";
const ALLOWED = new Set([
  "eth_call",
  "eth_chainId",
  "eth_getTransactionReceipt",
  "eth_getBlockByNumber",
  "eth_blockNumber",
  "eth_getCode",
  "eth_getBalance",
]);

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const items = Array.isArray(body) ? body : [body];
    if (!items.length || items.some((item) => !item || !ALLOWED.has(item.method))) {
      return NextResponse.json({ error: "Unsupported RPC method" }, { status: 400 });
    }
    const response = await fetch(UPSTREAM, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      cache: "no-store",
    });
    const text = await response.text();
    return new NextResponse(text, {
      status: response.status,
      headers: { "content-type": response.headers.get("content-type") ?? "application/json" },
    });
  } catch {
    return NextResponse.json({ error: "RPC proxy unavailable" }, { status: 502 });
  }
}
