import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "GapShield — Protect the gap. Keep the exposure.",
  description: "Fixed-price, fully collateralized downside protection for tokenized equities. Live testnet prototype on Robinhood Chain Testnet.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
