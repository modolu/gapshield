// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract SettlementFuzzTest is PoolTestBase {
    uint256 internal constant MAX_POLICIES = 12;

    function _epochWithTerms(uint256 trigger, uint256 cover) internal returns (uint256 epochId) {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.triggerBps = uint16(bound(trigger, 0, 5000));
        c.maxCoverBps = uint16(bound(cover, PREMIUM_BPS, 5000));
        c.maxAggregateLiability = 10_000_000 * USDG;
        epochId = _createEpoch(c);
    }

    function _buyMany(uint256 epochId, uint32[] memory units)
        internal
        returns (address[] memory buyers, uint256[] memory ids, uint256 n)
    {
        n = units.length > MAX_POLICIES ? MAX_POLICIES : units.length;
        buyers = new address[](n);
        ids = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            buyers[i] = address(uint160(0xB000 + i));
            ids[i] = _buy(buyers[i], epochId, bound(units[i], 10, 10_000) * USDG);
        }
    }

    struct Before {
        uint256 soldNotional;
        uint256 soldLiability;
        uint256 premiumCollected;
        uint256 lpAssets;
        uint256 reserved;
        uint256 pending;
    }

    /// Settlement accounting and claims in a fuzzed order: actualOwed <= soldLiability, sum of individual
    /// payouts == actualOwed, claims never exceed claimablePayouts, and the epoch drains to exactly zero.
    function testFuzz_settleAndClaimInAnyOrder(
        uint256 closePrice,
        uint256 openPrice,
        uint256 trigger,
        uint256 cover,
        uint32[] memory units,
        uint256 orderSeed
    ) public {
        vm.assume(units.length > 0);
        uint256 epochId = _epochWithTerms(trigger, cover);
        _deposit(lp1, 1_000_000 * USDG);
        (address[] memory buyers, uint256[] memory ids,) = _buyMany(epochId, units);

        Before memory b = _captureBefore(epochId);
        _settleBounded(epochId, closePrice, openPrice);
        uint256 actualOwed = _checkSettlementAccounting(epochId, b);

        assertEq(_sumPreviewPayouts(ids), actualOwed, "sum of individual payouts == actualOwed");
        assertEq(_claimAllInOrder(buyers, ids, orderSeed), actualOwed);
        assertEq(pool.claimablePayouts(), 0, "settled epoch contributes zero once all claimed");
        assertEq(
            usdg.balanceOf(address(pool)),
            pool.totalAssets() + pool.pendingPremium() + pool.claimablePayouts() + pool.protocolFeesAccrued()
        );
    }

    function _settleBounded(uint256 epochId, uint256 closePrice, uint256 openPrice) internal {
        closePrice = bound(closePrice, 1, 1e15);
        _settle(epochId, closePrice, bound(openPrice, 1, closePrice * 2));
    }

    function _sumPreviewPayouts(uint256[] memory ids) internal view returns (uint256 sum) {
        for (uint256 i; i < ids.length; ++i) {
            sum += pool.previewPayout(ids[i]);
        }
    }

    function _captureBefore(uint256 epochId) internal view returns (Before memory b) {
        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        b = Before({
            soldNotional: s.soldNotional,
            soldLiability: s.soldLiability,
            premiumCollected: s.premiumCollected,
            lpAssets: pool.totalAssets(),
            reserved: pool.reservedLiability(),
            pending: pool.pendingPremium()
        });
    }

    function _checkSettlementAccounting(uint256 epochId, Before memory b) internal view returns (uint256 actualOwed) {
        uint256 covered = pool.getEpochState(epochId).coveredBps;
        actualOwed = b.soldNotional * covered / 10_000;
        uint256 fee = b.premiumCollected * pool.getEpochConfig(epochId).protocolFeeBps / 10_000;
        assertLe(actualOwed, b.soldLiability, "actualOwed <= soldLiability");
        assertEq(pool.claimablePayouts(), actualOwed);
        assertEq(pool.reservedLiability(), b.reserved - b.soldLiability);
        assertEq(pool.pendingPremium(), b.pending - b.premiumCollected);
        assertEq(pool.protocolFeesAccrued(), fee);
        assertEq(pool.totalAssets(), b.lpAssets - actualOwed + b.premiumCollected - fee);
    }

    /// Claims every policy in a seed-driven (Fisher-Yates) order; returns the total claimed.
    function _claimAllInOrder(address[] memory buyers, uint256[] memory ids, uint256 seed)
        internal
        returns (uint256 claimed)
    {
        uint256 n = ids.length;
        uint256[] memory order = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            order[i] = i;
        }
        for (uint256 i = n; i > 1; --i) {
            uint256 j = uint256(keccak256(abi.encode(seed, i))) % i;
            (order[i - 1], order[j]) = (order[j], order[i - 1]);
        }
        for (uint256 i; i < n; ++i) {
            uint256 k = order[i];
            uint256 remaining = pool.claimablePayouts();
            uint256 got = _claim(buyers[k], ids[k]);
            assertLe(got, remaining, "a claim never exceeds claimablePayouts");
            assertLe(got, pool.getPolicy(ids[k]).maxPayout);
            claimed += got;
        }
    }

    /// Void then refund in a fuzzed order: the epoch's escrow drains to exactly zero, claimable untouched.
    function testFuzz_voidRefundAnyOrder(uint32[] memory units, uint256 orderSeed, uint256 voidDelay) public {
        vm.assume(units.length > 0);
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 1_000_000 * USDG);
        // Default epoch caps aggregate liability at 2,500 USDG: five max-size policies fit exactly.
        uint256 n = units.length > 5 ? 5 : units.length;
        address[] memory buyers = new address[](n);
        uint256[] memory ids = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            buyers[i] = address(uint160(0xC000 + i));
            ids[i] = _buy(buyers[i], epochId, bound(units[i], 10, 10_000) * USDG);
        }
        uint256 lpBefore = pool.totalAssets();

        vm.warp(SETTLEMENT_DEADLINE + bound(voidDelay, 0, 365 days));
        pool.voidEpoch(epochId);
        assertEq(pool.reservedLiability(), 0);
        assertEq(pool.totalAssets(), lpBefore);

        uint256 refunded;
        for (uint256 r; r < n; ++r) {
            uint256 k = (uint256(keccak256(abi.encode(orderSeed, r))) % n);
            if (pool.getPolicy(ids[k]).claimed) {
                // pick the first unclaimed instead
                for (k = 0; pool.getPolicy(ids[k]).claimed; ++k) {}
            }
            uint256 pendingBefore = pool.pendingPremium();
            uint256 got = _claim(buyers[k], ids[k]);
            assertEq(got, pool.getPolicy(ids[k]).premiumUSDG);
            assertEq(pool.pendingPremium(), pendingBefore - got);
            assertEq(pool.claimablePayouts(), 0, "refunds never touch claimablePayouts");
            refunded += got;
        }
        assertEq(refunded, pool.getEpochState(epochId).premiumCollected);
        assertEq(pool.pendingPremium(), 0, "voided epoch contributes zero once all refunded");
    }

    /// Settlement and void windows never overlap, around the exact deadline.
    function testFuzz_deadlineBoundary(int256 offset) public {
        offset = bound(offset, -2 days, 2 days);
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 10_000 * USDG);
        _buy(buyer1, epochId, 1000 * USDG);
        _settleClose(epochId, 10_000_000);
        vm.warp(OPEN_WINDOW_START);
        bytes memory data = _snapshot(9_100_000, OPEN_WINDOW_START);

        uint256 t = uint256(int256(uint256(SETTLEMENT_DEADLINE)) + offset);
        vm.assume(t >= OPEN_WINDOW_START);
        vm.warp(t);

        bool beforeDeadline = t < SETTLEMENT_DEADLINE;
        vm.prank(operator);
        (bool settled,) = address(pool).call(abi.encodeCall(ProtectionPool.settleOpen, (epochId, data)));
        (bool voided,) = address(pool).call(abi.encodeCall(ProtectionPool.voidEpoch, (epochId)));

        assertEq(settled, beforeDeadline, "settlement succeeds iff block.timestamp < deadline");
        assertEq(voided, !beforeDeadline, "void succeeds iff block.timestamp >= deadline");
        assertFalse(settled && voided, "never both");
        ProtectionPool.EpochStatus status = pool.getEpochState(epochId).status;
        assertEq(
            uint8(status),
            uint8(beforeDeadline ? ProtectionPool.EpochStatus.Settled : ProtectionPool.EpochStatus.Voided)
        );
    }

    /// The pool rejects any reference whose time is outside the half-open window.
    function testFuzz_referenceTimeWindow(uint64 refTime) public {
        uint256 epochId = _createDefaultEpoch();
        refTime = uint64(bound(refTime, CLOSE_WINDOW_START - 1 hours, CLOSE_WINDOW_END + 1 hours));
        vm.warp(CLOSE_WINDOW_END + 2 hours);
        bytes memory data = _snapshot(10_000_000, refTime);
        bool inWindow = refTime >= CLOSE_WINDOW_START && refTime < CLOSE_WINDOW_END;
        vm.prank(operator);
        (bool ok,) = address(pool).call(abi.encodeCall(ProtectionPool.settleClose, (epochId, data)));
        assertEq(ok, inWindow);
    }
}
