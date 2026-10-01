// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

/// @notice Deterministic end-to-end lifecycle scenarios (TESTNET DEMO ORACLE / SnapshotOracle, MockUSDG).
contract LifecycleTest is PoolTestBase {
    uint256 internal constant P100 = 10_000_000;
    uint256 internal constant LP_CAPITAL = 10_000 * USDG;

    function _assertBalanceCoversBuckets() internal view {
        assertEq(
            usdg.balanceOf(address(pool)),
            pool.totalAssets() + pool.pendingPremium() + pool.claimablePayouts() + pool.protocolFeesAccrued(),
            "every token in the pool belongs to exactly one bucket"
        );
    }

    /// Scenario A — calm weekend: close 100, open 98 -> no payout; LPs earn 88% of premium.
    function test_scenarioA_calmWeekend() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, LP_CAPITAL);
        uint256 policyId = _buy(buyer1, epochId, 1000 * USDG);
        assertEq(pool.pendingPremium(), 8 * USDG);

        _settle(epochId, P100, 9_800_000);
        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(uint8(s.status), uint8(ProtectionPool.EpochStatus.Settled));
        assertEq(s.gapBps, 200);
        assertEq(s.coveredBps, 0);
        assertEq(pool.claimablePayouts(), 0);

        assertEq(_claim(buyer1, policyId), 0, "buyer finalizes a zero payout");
        assertTrue(pool.getPolicy(policyId).claimed);

        assertEq(pool.totalAssets(), LP_CAPITAL + 7_040_000, "LP capital + 88% of 8 USDG");
        assertEq(pool.protocolFeesAccrued(), 960_000, "12% of 8 USDG");
        assertEq(pool.reservedLiability(), 0);
        assertEq(pool.pendingPremium(), 0);
        _assertBalanceCoversBuckets();

        uint256 shares = pool.balanceOf(lp1);
        vm.prank(lp1);
        assertEq(
            pool.redeem(shares, lp1, lp1),
            LP_CAPITAL + 7_040_000 - 1,
            "LP exits with premium (1 wei virtual-share rounding)"
        );
    }

    /// Scenario B — triggered weekend: 1,000 USDG, 5%/5%, close 100 -> open 91 -> 40 USDG.
    function test_scenarioB_triggeredWeekend() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, LP_CAPITAL);
        uint256 policyId = _buy(buyer1, epochId, 1000 * USDG);

        _settle(epochId, P100, 9_100_000);
        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(s.gapBps, 900, "adverse gap 9%");
        assertEq(s.coveredBps, 400, "covered excess 4%");
        assertEq(pool.claimablePayouts(), 40 * USDG);
        assertEq(pool.totalAssets(), LP_CAPITAL - 40 * USDG + 7_040_000);
        _assertBalanceCoversBuckets();

        assertEq(_claim(buyer1, policyId), 40 * USDG);
        assertEq(usdg.balanceOf(buyer1), 40 * USDG);
        assertEq(pool.claimablePayouts(), 0);
        _assertBalanceCoversBuckets();
    }

    /// Scenario C — beyond cap: payout capped at 50 USDG for 1,000 USDG notional (incl. the -12% demo).
    function test_scenarioC_beyondCap() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, LP_CAPITAL);
        uint256 policyId = _buy(buyer1, epochId, 1000 * USDG);
        _settle(epochId, P100, 8_800_000);
        assertEq(pool.getEpochState(epochId).coveredBps, 500);
        assertEq(pool.claimablePayouts(), 50 * USDG);
        assertEq(_claim(buyer1, policyId), 50 * USDG);
        assertEq(pool.claimablePayouts(), 0);
        _assertBalanceCoversBuckets();
    }

    /// Scenario D — oracle failure: no settlement, deadline passes, a third party voids, buyer is refunded.
    function test_scenarioD_oracleFailureVoidRefund() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, LP_CAPITAL);
        uint256 policyId = _buy(buyer1, epochId, 1000 * USDG);
        assertEq(pool.reservedLiability(), 50 * USDG);

        vm.warp(SETTLEMENT_DEADLINE);
        vm.prank(makeAddr("anyone"));
        pool.voidEpoch(epochId);

        assertEq(pool.reservedLiability(), 0, "reserve released");
        assertEq(pool.totalAssets(), LP_CAPITAL, "LP capital whole");
        assertEq(_claim(buyer1, policyId), 8 * USDG, "full premium refund");
        assertEq(usdg.balanceOf(buyer1), 8 * USDG);
        assertEq(pool.pendingPremium(), 0);
        assertEq(pool.claimablePayouts(), 0, "no claimable payouts involved");
        assertEq(pool.protocolFeesAccrued(), 0, "no fee on a voided epoch");
        _assertBalanceCoversBuckets();
    }

    /// Scenario E — multiple policies: aggregate owed equals the sum of claims made in arbitrary order.
    function test_scenarioE_multiplePolicies() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, LP_CAPITAL);
        _deposit(lp2, LP_CAPITAL);
        address[5] memory buyers = [buyer1, buyer2, makeAddr("buyer3"), makeAddr("buyer4"), makeAddr("buyer5")];
        uint256[5] memory notionals = [uint256(17), 1000, 333, 9999, 2468];
        uint256[5] memory ids;
        uint256 soldNotional;
        for (uint256 i; i < 5; ++i) {
            ids[i] = _buy(buyers[i], epochId, notionals[i] * USDG);
            soldNotional += notionals[i] * USDG;
        }

        _settle(epochId, P100, 9_277_777); // gap 722 bps -> covered 222 bps
        uint256 covered = pool.getEpochState(epochId).coveredBps;
        assertEq(covered, 222);
        uint256 actualOwed = soldNotional * covered / 10_000;
        assertEq(pool.claimablePayouts(), actualOwed);

        uint256[5] memory order = [uint256(3), 0, 4, 2, 1];
        uint256 claimed;
        for (uint256 i; i < 5; ++i) {
            uint256 k = order[i];
            uint256 got = _claim(buyers[k], ids[k]);
            assertEq(got, notionals[k] * USDG * covered / 10_000);
            claimed += got;
            _assertBalanceCoversBuckets();
        }
        assertEq(claimed, actualOwed, "sum of claims == actualOwed");
        assertEq(pool.claimablePayouts(), 0, "claimablePayouts drains exactly to zero");
    }

    /// Full LP cycle across two epochs: void then settle, with deposits/withdrawals unlocking in between.
    function test_twoEpochCycle_lpLocksAndUnlocks() public {
        uint256 e1 = _createDefaultEpoch();
        _deposit(lp1, LP_CAPITAL);
        _buy(buyer1, e1, 1000 * USDG);
        vm.warp(SALE_CUTOFF);
        assertEq(pool.maxWithdraw(lp1), 0, "locked after cutoff");
        vm.warp(SETTLEMENT_DEADLINE);
        pool.voidEpoch(e1);
        assertEq(pool.maxWithdraw(lp1), LP_CAPITAL, "unlocked after void");

        uint256 e2 = _createEpoch(_shiftedConfig(7 days));
        _deposit(lp2, 5000 * USDG); // deposits reopen with the new epoch, before its cutoff
        uint256 p2 = _buy(buyer2, e2, 2000 * USDG);
        _settle(e2, P100, 9_000_000);
        assertEq(_claim(buyer2, p2), 100 * USDG);
        assertEq(_claim(buyer1, 1), 8 * USDG, "epoch 1 refund survives epoch 2 settlement");
        assertEq(pool.pendingPremium(), 0);
        assertEq(pool.claimablePayouts(), 0);
        _assertBalanceCoversBuckets();
    }
}
