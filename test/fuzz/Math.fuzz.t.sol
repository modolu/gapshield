// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {MathHarness} from "../utils/MathHarness.sol";

contract MathFuzzTest is Test {
    uint256 internal constant USDG = 1e6;
    uint256 internal constant MAX_UNITS = 10_000_000; // 10M USDG per policy, far above any configured max
    uint256 internal constant MAX_PRICE = type(uint128).max;

    MathHarness internal m;

    function setUp() public {
        m = new MathHarness();
    }

    function _terms(uint256 trigger, uint256 cover) internal pure returns (uint256 t, uint256 c) {
        t = bound(trigger, 0, 5000);
        c = bound(cover, 1, 5000);
    }

    function testFuzz_payoutNeverExceedsMaxPayout(
        uint256 units,
        uint256 closePrice,
        uint256 openPrice,
        uint256 trigger,
        uint256 cover
    ) public view {
        uint256 notional = bound(units, 1, MAX_UNITS) * USDG;
        closePrice = bound(closePrice, 1, MAX_PRICE);
        openPrice = bound(openPrice, 0, MAX_PRICE);
        (uint256 t, uint256 c) = _terms(trigger, cover);
        assertLe(m.payoutFor(notional, closePrice, openPrice, t, c), m.maxPayout(notional, c));
    }

    function testFuzz_payoutZeroWhenGapWithinTrigger(
        uint256 units,
        uint256 closePrice,
        uint256 openPrice,
        uint256 trigger,
        uint256 cover
    ) public view {
        uint256 notional = bound(units, 1, MAX_UNITS) * USDG;
        closePrice = bound(closePrice, 1, MAX_PRICE);
        openPrice = bound(openPrice, 0, MAX_PRICE);
        (uint256 t, uint256 c) = _terms(trigger, cover);
        uint256 gap = m.gapBps(closePrice, openPrice);
        vm.assume(gap <= t);
        assertEq(m.payoutFor(notional, closePrice, openPrice, t, c), 0);
    }

    function testFuzz_upwardOrFlatOpenNeverPays(uint256 units, uint256 closePrice, uint256 rise, uint256 t, uint256 c)
        public
        view
    {
        uint256 notional = bound(units, 1, MAX_UNITS) * USDG;
        closePrice = bound(closePrice, 1, MAX_PRICE);
        uint256 openPrice = closePrice + bound(rise, 0, MAX_PRICE);
        (t, c) = _terms(t, c);
        assertEq(m.payoutFor(notional, closePrice, openPrice, t, c), 0);
    }

    function testFuzz_payoutMonotonicInAdverseGap(
        uint256 units,
        uint256 closePrice,
        uint256 openA,
        uint256 openB,
        uint256 trigger,
        uint256 cover
    ) public view {
        uint256 notional = bound(units, 1, MAX_UNITS) * USDG;
        closePrice = bound(closePrice, 1, MAX_PRICE);
        openA = bound(openA, 0, closePrice);
        openB = bound(openB, 0, openA); // openB <= openA: wider or equal adverse gap
        (uint256 t, uint256 c) = _terms(trigger, cover);
        assertGe(m.payoutFor(notional, closePrice, openB, t, c), m.payoutFor(notional, closePrice, openA, t, c));
    }

    function testFuzz_payoutReachesCapOnceGapExceedsTriggerPlusCover(
        uint256 units,
        uint256 closePrice,
        uint256 openPrice,
        uint256 trigger,
        uint256 cover
    ) public view {
        uint256 notional = bound(units, 1, MAX_UNITS) * USDG;
        closePrice = bound(closePrice, 1, MAX_PRICE);
        openPrice = bound(openPrice, 0, closePrice);
        (uint256 t, uint256 c) = _terms(trigger, cover);
        vm.assume(m.gapBps(closePrice, openPrice) >= t + c);
        assertEq(m.payoutFor(notional, closePrice, openPrice, t, c), m.maxPayout(notional, c));
    }

    function testFuzz_premiumRoundsUpByLessThanOneUnit(uint256 notional, uint256 premiumBps) public view {
        notional = bound(notional, 0, type(uint128).max);
        premiumBps = bound(premiumBps, 0, 10_000);
        uint256 p = m.premium(notional, premiumBps);
        uint256 exactTimesBps = notional * premiumBps;
        assertGe(p * 10_000, exactTimesBps, "premium never below exact value");
        assertLt(p * 10_000, exactTimesBps + 10_000, "premium rounds up by < 1 base unit");
    }

    function testFuzz_wholeUsdgPremiumAndMaxPayoutAreExact(uint256 units, uint256 premiumBps, uint256 cover)
        public
        view
    {
        uint256 notional = bound(units, 1, MAX_UNITS) * USDG;
        premiumBps = bound(premiumBps, 1, 10_000);
        cover = bound(cover, 1, 10_000);
        assertEq(m.premium(notional, premiumBps) * 10_000, notional * premiumBps);
        assertEq(m.maxPayout(notional, cover) * 10_000, notional * cover);
    }

    function testFuzz_protocolFeeNeverExceedsPremium(uint256 premium, uint256 feeBps) public view {
        premium = bound(premium, 0, type(uint128).max);
        feeBps = bound(feeBps, 0, 10_000);
        uint256 fee = m.protocolFee(premium, feeBps);
        assertLe(fee, premium);
        assertLe(fee * 10_000, premium * feeBps, "fee rounds down");
    }

    /// @notice Architecture §7 / PHASE0 §9 P5: with whole-USDG notionals the O(1) aggregate settlement
    /// liability equals the sum of individually rounded-down payouts, for every integer coveredBps.
    function testFuzz_aggregateSettledLiabilityEqualsSumOfIndividualPayouts(uint32[] calldata units, uint256 covered)
        public
        view
    {
        vm.assume(units.length > 0 && units.length <= 64);
        covered = bound(covered, 0, 10_000);
        uint256 soldNotional;
        uint256 sumOfPayouts;
        for (uint256 i; i < units.length; ++i) {
            uint256 notional = (uint256(units[i]) + 1) * USDG;
            soldNotional += notional;
            sumOfPayouts += m.payout(notional, covered);
        }
        assertEq(m.payout(soldNotional, covered), sumOfPayouts);
    }

    /// @notice Why whole USDG is required: for arbitrary base-unit notionals the aggregate can exceed the sum
    /// (dust). This documents the hazard the whole-USDG rule removes; it is never less than the sum.
    function testFuzz_aggregateNeverBelowSumForArbitraryNotionals(uint64[] calldata notionals, uint256 covered)
        public
        view
    {
        vm.assume(notionals.length > 0 && notionals.length <= 64);
        covered = bound(covered, 0, 10_000);
        uint256 total;
        uint256 sum;
        for (uint256 i; i < notionals.length; ++i) {
            total += notionals[i];
            sum += m.payout(notionals[i], covered);
        }
        assertGe(m.payout(total, covered), sum);
    }

    function test_arbitraryNotionalsCanCreateDust() public view {
        // Two 0.5-unit-of-a-bp payouts: individually 0 each, aggregate 1 -> dust. Whole USDG prevents this.
        assertEq(m.payout(5000, 1) + m.payout(5000, 1), 0);
        assertEq(m.payout(10_000, 1), 1);
    }
}
