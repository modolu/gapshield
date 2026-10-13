-- GapShield demo browser automation — under 2 minutes
-- Creates a dedicated Chrome window, preloads all demo pages, then advances them on a timed sequence.

set readmeTop to "https://github.com/modolu/gapshield"
set readmeHow to "https://github.com/modolu/gapshield#how-it-works"
set readmeDeploy to "https://github.com/modolu/gapshield#live-deployment--robinhood-chain-testnet-chain-id-46630"
set lpTx to "https://explorer.testnet.chain.robinhood.com/tx/0x6ee94fa32f1d9068540dad97ff5739c37610687b41d0a0605189a2886dafca0e"
set purchaseTx to "https://explorer.testnet.chain.robinhood.com/tx/0xc981a8e030d3e5f7693d84d0a2302a9ad8e5d4c5cde1afec3260542972c8c22b"
set settlementTx to "https://explorer.testnet.chain.robinhood.com/tx/0x0b5f6ec5b38270c41aadfa0f0c4fc69536117072a4aaf1b2ae0972bbb18a6021"
set claimTx to "https://explorer.testnet.chain.robinhood.com/tx/0x3f30b8dd781cbbd176d6a4d27b54c006522aeda0cfc1373c39e958d9832437b4"
set evidenceAccounting to "https://github.com/modolu/gapshield/blob/main/docs/TESTNET_DEMO_EVIDENCE.md#accounting-read-back-from-the-chain"
set readmeSafety to "https://github.com/modolu/gapshield#safety-model"

tell application "Google Chrome"
  activate
  set priorBounds to bounds of front window
  set demoWindow to make new window
  set bounds of demoWindow to priorBounds
  set URL of active tab of demoWindow to readmeTop
  make new tab at end of tabs of demoWindow with properties {URL:readmeHow}
  make new tab at end of tabs of demoWindow with properties {URL:readmeDeploy}
  make new tab at end of tabs of demoWindow with properties {URL:lpTx}
  make new tab at end of tabs of demoWindow with properties {URL:purchaseTx}
  make new tab at end of tabs of demoWindow with properties {URL:settlementTx}
  make new tab at end of tabs of demoWindow with properties {URL:claimTx}
  make new tab at end of tabs of demoWindow with properties {URL:evidenceAccounting}
  make new tab at end of tabs of demoWindow with properties {URL:readmeSafety}
  set active tab index of demoWindow to 1
end tell

-- Short preload buffer.
delay 5

-- Scene 1: Problem — 12 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 1
delay 12

-- Scene 2: How it works — 14 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 2
delay 14

-- Scene 3: Live deployment — 8 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 3
delay 8

-- Scene 4: LP liquidity — 10 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 4
delay 10

-- Scene 5: Protection purchase — 14 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 5
delay 14

-- Scene 6: 100 -> 91 settlement — 18 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 6
delay 18

-- Scene 7: 40 USDG claim — 10 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 7
delay 10

-- Scene 8: Final accounting / evidence — 15 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 8
delay 15

-- Scene 9: Closing pitch — 9 seconds
tell application "Google Chrome" to set active tab index of demoWindow to 9
delay 9

-- End on README top for a clean final frame
tell application "Google Chrome" to set active tab index of demoWindow to 1
