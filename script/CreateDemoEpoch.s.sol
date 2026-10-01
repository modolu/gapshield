// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script, console2} from "forge-std/Script.sol";

import {ProtectionPool} from "../contracts/ProtectionPool.sol";

/// @notice Opens a compressed TESTNET DEMO epoch (minutes, not a real weekend) settled by the SnapshotOracle.
/// Economics are the frozen Phase 0 tier: trigger 5%, cover 5%, premium 0.80%, fee 12%, 10–10,000 USDG notional,
/// 2,500 USDG aggregate liability. Must be broadcast by the pool owner.
///
/// Env: POOL, ORACLE (required); DEMO_SALE_MINUTES (default 10), DEMO_GAP_MINUTES (default 5),
/// DEMO_WINDOW_MINUTES (default 5), DEMO_DEADLINE_MINUTES (default 30).
/// Timeline from now: sales close at +sale; close window [cutoff, +window); open window starts +gap after it;
/// settlement deadline +deadline after the open window ends.
contract CreateDemoEpoch is Script {
    bytes32 public constant TSLA = keccak256("TSLA");
    uint256 internal constant USDG = 1e6;

    function run() external returns (uint256 epochId) {
        ProtectionPool pool = ProtectionPool(vm.envAddress("POOL"));
        address oracle = vm.envAddress("ORACLE");
        uint64 saleMin = uint64(vm.envOr("DEMO_SALE_MINUTES", uint256(10)));
        uint64 gapMin = uint64(vm.envOr("DEMO_GAP_MINUTES", uint256(5)));
        uint64 windowMin = uint64(vm.envOr("DEMO_WINDOW_MINUTES", uint256(5)));
        uint64 deadlineMin = uint64(vm.envOr("DEMO_DEADLINE_MINUTES", uint256(30)));

        ProtectionPool.EpochConfig memory c;
        c.assetId = TSLA;
        c.oracle = oracle;
        c.saleCutoff = uint64(block.timestamp) + saleMin * 60;
        c.closeWindowStart = c.saleCutoff;
        c.closeWindowEnd = c.closeWindowStart + windowMin * 60;
        c.openWindowStart = c.closeWindowEnd + gapMin * 60;
        c.openWindowEnd = c.openWindowStart + windowMin * 60;
        c.settlementDeadline = c.openWindowEnd + deadlineMin * 60;
        c.triggerBps = 500;
        c.maxCoverBps = 500;
        c.premiumBps = 80;
        c.protocolFeeBps = 1200;
        c.minNotional = 10 * USDG;
        c.maxNotional = 10_000 * USDG;
        c.maxAggregateLiability = 2500 * USDG;

        vm.broadcast();
        epochId = pool.createEpoch(c);

        console2.log("TESTNET DEMO epoch", epochId);
        console2.log("saleCutoff        ", c.saleCutoff);
        console2.log("closeWindow       ", c.closeWindowStart, c.closeWindowEnd);
        console2.log("openWindow        ", c.openWindowStart, c.openWindowEnd);
        console2.log("settlementDeadline", c.settlementDeadline);
    }
}
