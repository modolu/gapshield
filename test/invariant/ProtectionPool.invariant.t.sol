// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {PoolHandler} from "./PoolHandler.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

/// @notice Full-lifecycle invariants (Architecture §16, Phase 2 brief 1–15). The handler creates epochs itself,
/// settles or voids them, and claims/refunds policies, all interleaved with LP flows, pause and donations.
/// forge-config: default.invariant.depth = 128
/// forge-config: ci.invariant.depth = 128
contract ProtectionPoolInvariantTest is StdInvariant, PoolTestBase {
    PoolHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new PoolHandler(pool, oracle, usdg, owner, operator, TSLA, TSLA_FEED_ID);
        // The handler posts snapshots as the oracle owner; it uses `owner` for both roles.
        targetContract(address(handler));
    }

    // 1. reservedLiability <= LP-owned (claim-supporting) collateral, always.
    function invariant_01_reservedWithinLpAssets() public view {
        assertLe(pool.reservedLiability(), pool.totalAssets());
    }

    // 2. claimablePayouts == aggregate settled-unclaimed policy payouts.
    function invariant_02_claimableEqualsSettledUnclaimed() public view {
        uint256 sum;
        for (uint256 i; i < handler.policyCount(); ++i) {
            uint256 id = handler.policyIds(i);
            ProtectionPool.Policy memory p = pool.getPolicy(id);
            ProtectionPool.EpochState memory s = pool.getEpochState(p.epochId);
            if (s.status == ProtectionPool.EpochStatus.Settled && !p.claimed) {
                sum += p.notional * s.coveredBps / 10_000;
            }
        }
        assertEq(pool.claimablePayouts(), sum);
    }

    // 3. pendingPremium == premium neither allocated by settlement nor refunded.
    function invariant_03_pendingEqualsUnallocatedUnrefunded() public view {
        uint256 sum;
        for (uint256 i; i < handler.policyCount(); ++i) {
            uint256 id = handler.policyIds(i);
            ProtectionPool.Policy memory p = pool.getPolicy(id);
            ProtectionPool.EpochStatus st = pool.getEpochState(p.epochId).status;
            bool live = st == ProtectionPool.EpochStatus.Open || st == ProtectionPool.EpochStatus.CloseRecorded;
            bool unrefunded = st == ProtectionPool.EpochStatus.Voided && !p.claimed;
            if (live || unrefunded) sum += p.premiumUSDG;
        }
        assertEq(pool.pendingPremium(), sum);
    }

    // 4. USDG balance >= totalAssets + pendingPremium + claimablePayouts + protocolFeesAccrued
    //    (exactly equal plus unsolicited donations, which are never credited to any bucket).
    function invariant_04_balanceCoversAllBuckets() public view {
        uint256 buckets =
            pool.totalAssets() + pool.pendingPremium() + pool.claimablePayouts() + pool.protocolFeesAccrued();
        assertGe(usdg.balanceOf(address(pool)), buckets);
        assertEq(usdg.balanceOf(address(pool)), buckets + handler.ghostDonations());
    }

    // 5. Free collateral excludes claimable payouts, premium escrow and protocol fees: LP-owned assets match the
    //    independent model, which never adds those buckets to LP capital.
    function invariant_05_freeCollateralExcludesNonLpBuckets() public view {
        assertEq(pool.totalAssets(), handler.ghostLpAssets());
        assertEq(pool.freeCollateral(), handler.ghostLpAssets() - handler.ghostReserved());
        assertEq(pool.reservedLiability(), handler.ghostReserved());
        assertEq(pool.pendingPremium(), handler.ghostPending());
        assertEq(pool.claimablePayouts(), handler.ghostClaimable());
        assertEq(pool.protocolFeesAccrued(), handler.ghostFees());
    }

    // 6–9. LP withdrawals cannot consume reserved liability, settled claimable payouts, refundable premium or
    //      protocol fees: no LP is ever offered more than free collateral, and the handler verifies after every
    //      withdraw/redeem that the reserve, escrow, claimable and fee buckets are unchanged.
    function invariant_06_09_withdrawalsBoundedToLpBucket() public view {
        for (uint256 i; i < handler.lpCount(); ++i) {
            address lp = handler.lps(i);
            assertLe(pool.maxWithdraw(lp), pool.freeCollateral());
            assertLe(pool.previewRedeem(pool.maxRedeem(lp)), pool.freeCollateral());
        }
        assertEq(handler.ghostUnexpected(), 0, handler.lastUnexpected());
    }

    // 10–12. Settled references never change; Settled never becomes Voided; Voided never settles.
    function invariant_10_12_terminalStatesAndReferencesFrozen() public view {
        for (uint256 i; i < handler.epochCount(); ++i) {
            uint256 id = handler.epochIds(i);
            PoolHandler.GhostEpoch memory g = handler.ghostEpoch(id);
            ProtectionPool.EpochState memory s = pool.getEpochState(id);
            assertEq(uint8(s.status), uint8(g.status), "on-chain status matches the model");
            if (g.status == ProtectionPool.EpochStatus.Settled) {
                assertEq(handler.refsHash(id), g.refsHash, "settled references frozen");
            }
            if (g.status == ProtectionPool.EpochStatus.Voided) {
                assertEq(s.openPrice, 0, "a voided epoch never recorded an open");
            }
        }
    }

    // 13. No policy can claim or refund twice.
    function invariant_13_noDoubleClaim() public view {
        for (uint256 i; i < handler.policyCount(); ++i) {
            uint256 id = handler.policyIds(i);
            PoolHandler.GhostPolicy memory g = handler.ghostPolicy(id);
            assertLe(g.claimCount, 1);
            assertEq(pool.getPolicy(id).claimed, g.claimed);
            assertEq(pool.getPolicy(id).maxPayout, g.maxPayout, "policy terms immutable");
            assertEq(receipt.ownerOf(id), g.owner, "receipt ownership fixed");
        }
        assertEq(handler.ghostReceiptTransferSuccesses(), 0);
    }

    // 14. claimablePayouts never becomes selling capacity: capacity is computed from LP-owned assets only.
    function invariant_14_claimableNotCapacity() public view {
        // Purchases are predicted with capacity = ghostLpAssets * cap; any purchase enabled by claimable money
        // would have registered as an unexpected outcome. Also check the bucket is disjoint from LP assets.
        assertEq(pool.totalAssets(), handler.ghostLpAssets());
        assertLe(pool.reservedLiability(), pool.totalAssets());
        assertEq(handler.ghostUnexpected(), 0, handler.lastUnexpected());
    }

    // 15. Pause cannot trap valid settlement, claims, refunds, void or free-collateral withdrawal: the handler's
    //     model ignores pause for those actions, so any pause-induced revert is an unexpected outcome.
    function invariant_15_pauseNeverTrapsFunds() public view {
        assertEq(handler.ghostUnexpected(), 0, handler.lastUnexpected());
    }
}
