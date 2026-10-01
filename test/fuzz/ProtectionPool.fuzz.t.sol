// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolFuzzTest is PoolTestBase {
    function testFuzz_nonWholeUsdgNotionalRejected(uint256 units, uint256 dust) public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 1_000_000 * USDG);
        uint256 notional = bound(units, 10, 9999) * USDG + bound(dust, 1, USDG - 1);
        _fundBuyer(buyer1, 1000 * USDG);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.NotionalNotWholeUSDG.selector, notional));
        pool.buyProtection(epochId, notional);
    }

    uint256 internal constant MAX_PURCHASES = 24;

    /// @dev Builds a purchase list of 1..MAX_PURCHASES whole-USDG unit counts without discarding inputs:
    /// the count comes from `countSeed`; fuzzer-provided entries are used first (so the fuzzer can still steer
    /// edge values) and any remainder is derived deterministically from `countSeed`.
    function _purchaseUnits(uint32[] calldata fuzzed, uint256 countSeed)
        internal
        pure
        returns (uint256[] memory units)
    {
        units = new uint256[](bound(countSeed, 1, MAX_PURCHASES));
        for (uint256 i; i < units.length; ++i) {
            uint256 raw = i < fuzzed.length ? fuzzed[i] : uint256(keccak256(abi.encode(countSeed, i)));
            units[i] = bound(raw, 10, 10_000);
        }
    }

    /// @dev Running model of a purchase sequence.
    struct Expected {
        uint256 reserved;
        uint256 notional;
        uint256 premium;
    }

    /// @dev Creates an epoch with fuzzed terms/caps, funds it, and returns its id, config and LP capital.
    function _setupFuzzedEpoch(uint256 lpCapital, uint256 maxAggregate, uint16 trigger, uint16 cover)
        internal
        returns (uint256 epochId, ProtectionPool.EpochConfig memory c, uint256 capital)
    {
        capital = bound(lpCapital, 1, 2_000_000) * USDG;
        c = _defaultConfig();
        c.maxAggregateLiability = bound(maxAggregate, 1, 1_000_000) * USDG;
        c.triggerBps = uint16(bound(trigger, 0, 5000));
        c.maxCoverBps = uint16(bound(cover, PREMIUM_BPS, 5000));
        epochId = _createEpoch(c);
        _deposit(lp1, capital);
        _fundBuyer(buyer1, type(uint128).max);
    }

    /// @notice Random sequences of purchases against random LP capital and epoch caps. Every purchase either
    /// succeeds with exact accounting or reverts with the capacity error the model predicts.
    function testFuzz_multiplePurchases(
        uint256 lpCapital,
        uint256 maxAggregate,
        uint16 trigger,
        uint16 cover,
        uint32[] calldata unitsList,
        uint256 countSeed
    ) public {
        uint256[] memory units = _purchaseUnits(unitsList, countSeed);
        (uint256 epochId, ProtectionPool.EpochConfig memory c, uint256 capital) =
            _setupFuzzedEpoch(lpCapital, maxAggregate, trigger, cover);
        uint256 capacity = Math.mulDiv(capital, UTILIZATION_CAP_BPS, 10_000);

        Expected memory e;
        for (uint256 i; i < units.length; ++i) {
            _buyAndCheck(epochId, c, capacity, units[i] * USDG, e);
        }

        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(s.soldNotional, e.notional);
        assertEq(s.soldLiability, e.reserved);
        assertEq(s.premiumCollected, e.premium);
        assertEq(pool.pendingPremium(), e.premium);
        assertEq(pool.totalAssets(), capital, "premium never becomes LP capital before settlement");
        assertEq(usdg.balanceOf(address(pool)), capital + e.premium);
    }

    /// @dev One purchase: predicts success or the exact capacity revert, then checks the reserve and caps.
    function _buyAndCheck(
        uint256 epochId,
        ProtectionPool.EpochConfig memory c,
        uint256 capacity,
        uint256 notional,
        Expected memory e
    ) internal {
        uint256 maxPayout = notional * c.maxCoverBps / 10_000;
        uint256 premium = Math.mulDiv(notional, PREMIUM_BPS, 10_000, Math.Rounding.Ceil);

        vm.prank(buyer1);
        if (e.reserved + maxPayout > capacity) {
            vm.expectRevert(
                abi.encodeWithSelector(ProtectionPool.PoolCapacityExceeded.selector, e.reserved + maxPayout, capacity)
            );
            pool.buyProtection(epochId, notional);
        } else if (e.reserved + maxPayout > c.maxAggregateLiability) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProtectionPool.EpochCapacityExceeded.selector, e.reserved + maxPayout, c.maxAggregateLiability
                )
            );
            pool.buyProtection(epochId, notional);
        } else {
            uint256 policyId = pool.buyProtection(epochId, notional);
            assertEq(pool.getPolicy(policyId).maxPayout, maxPayout);
            e.reserved += maxPayout;
            e.notional += notional;
            e.premium += premium;
        }

        assertEq(pool.reservedLiability(), e.reserved);
        assertLe(pool.reservedLiability(), capacity, "utilization cap never breached");
        assertLe(pool.getEpochState(epochId).soldLiability, c.maxAggregateLiability, "epoch cap never breached");
    }

    function testFuzz_withdrawalNeverBreachesReserve(uint256 lpCapital, uint256 units, uint256 withdrawAmount) public {
        lpCapital = bound(lpCapital, 100, 1_000_000) * USDG;
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, lpCapital);

        uint256 notional = bound(units, 10, 10_000) * USDG;
        _fundBuyer(buyer1, notional);
        vm.prank(buyer1);
        try pool.buyProtection(epochId, notional) {} catch {}

        uint256 maxW = pool.maxWithdraw(lp1);
        assertEq(maxW, pool.freeCollateral(), "single LP can withdraw exactly the free collateral");
        withdrawAmount = bound(withdrawAmount, 0, lpCapital);
        vm.prank(lp1);
        if (withdrawAmount > maxW) {
            vm.expectRevert();
            pool.withdraw(withdrawAmount, lp1, lp1);
        } else {
            pool.withdraw(withdrawAmount, lp1, lp1);
        }
        assertLe(pool.reservedLiability(), pool.totalAssets());
    }
}
