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

    /// @notice Random sequences of purchases against random LP capital and epoch caps. Every purchase either
    /// succeeds with exact accounting or reverts with the capacity error the model predicts.
    function testFuzz_multiplePurchases(
        uint256 lpCapital,
        uint256 maxAggregate,
        uint16 trigger,
        uint16 cover,
        uint32[] calldata unitsList
    ) public {
        vm.assume(unitsList.length > 0 && unitsList.length <= 24);
        lpCapital = bound(lpCapital, 1, 2_000_000) * USDG;
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxAggregateLiability = bound(maxAggregate, 1, 1_000_000) * USDG;
        c.triggerBps = uint16(bound(trigger, 0, 5000));
        c.maxCoverBps = uint16(bound(cover, PREMIUM_BPS, 5000));
        uint256 epochId = _createEpoch(c);
        _deposit(lp1, lpCapital);
        _fundBuyer(buyer1, type(uint128).max);

        uint256 expectedReserved;
        uint256 expectedNotional;
        uint256 expectedPremium;
        uint256 capacity = Math.mulDiv(lpCapital, UTILIZATION_CAP_BPS, 10_000);

        for (uint256 i; i < unitsList.length; ++i) {
            uint256 notional = bound(unitsList[i], 10, 10_000) * USDG;
            uint256 maxPayout = notional * c.maxCoverBps / 10_000;
            uint256 premium = Math.mulDiv(notional, PREMIUM_BPS, 10_000, Math.Rounding.Ceil);

            vm.prank(buyer1);
            if (expectedReserved + maxPayout > capacity) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ProtectionPool.PoolCapacityExceeded.selector, expectedReserved + maxPayout, capacity
                    )
                );
                pool.buyProtection(epochId, notional);
            } else if (expectedReserved + maxPayout > c.maxAggregateLiability) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ProtectionPool.EpochCapacityExceeded.selector,
                        expectedReserved + maxPayout,
                        c.maxAggregateLiability
                    )
                );
                pool.buyProtection(epochId, notional);
            } else {
                uint256 policyId = pool.buyProtection(epochId, notional);
                assertEq(pool.getPolicy(policyId).maxPayout, maxPayout);
                expectedReserved += maxPayout;
                expectedNotional += notional;
                expectedPremium += premium;
            }

            assertEq(pool.reservedLiability(), expectedReserved);
            assertLe(pool.reservedLiability(), capacity, "utilization cap never breached");
            assertLe(pool.getEpochState(epochId).soldLiability, c.maxAggregateLiability, "epoch cap never breached");
        }

        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(s.soldNotional, expectedNotional);
        assertEq(s.soldLiability, expectedReserved);
        assertEq(s.premiumCollected, expectedPremium);
        assertEq(pool.pendingPremium(), expectedPremium);
        assertEq(pool.totalAssets(), lpCapital, "premium never becomes LP capital before settlement");
        assertEq(usdg.balanceOf(address(pool)), lpCapital + expectedPremium);
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
