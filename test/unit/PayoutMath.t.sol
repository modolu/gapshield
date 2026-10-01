// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {MathHarness} from "../utils/MathHarness.sol";
import {PayoutMath} from "../../contracts/libraries/PayoutMath.sol";

contract PayoutMathTest is Test {
    uint256 internal constant USDG = 1e6;
    uint256 internal constant N = 1000 * USDG;
    uint256 internal constant T = 500;
    uint256 internal constant C = 500;
    /// @dev Pyth TSLA exponent is -5: 100.00000 USD = 10_000_000.
    uint256 internal constant FRIDAY = 10_000_000;

    MathHarness internal m;

    function setUp() public {
        m = new MathHarness();
    }

    function _payout(uint256 openPrice) internal view returns (uint256) {
        return m.payoutFor(N, FRIDAY, openPrice, T, C);
    }

    function test_noDownsideGap() public view {
        assertEq(m.gapBps(FRIDAY, FRIDAY), 0);
        assertEq(_payout(FRIDAY), 0);
    }

    function test_upwardGap() public view {
        assertEq(m.gapBps(FRIDAY, 11_000_000), 0);
        assertEq(_payout(11_000_000), 0);
    }

    function test_exactlyTrigger() public view {
        assertEq(m.gapBps(FRIDAY, 9_500_000), 500);
        assertEq(_payout(9_500_000), 0);
    }

    function test_triggerPlusOneBp() public view {
        assertEq(m.gapBps(FRIDAY, 9_499_000), 501);
        assertEq(_payout(9_499_000), 100_000); // 1 bp of 1,000 USDG = 0.10 USDG
    }

    function test_betweenTriggerAndCap_architectureExample() public view {
        // Architecture §7: Friday 100, Monday 91 -> gap 9% -> covered 4% -> 40 USDG
        assertEq(m.gapBps(FRIDAY, 9_100_000), 900);
        assertEq(_payout(9_100_000), 40 * USDG);
    }

    function test_betweenTriggerAndCap_briefMagicMoment() public view {
        // Brief §7: Friday 100.00, Monday 91.60 -> gap 8.40% -> covered 3.40% -> 34 USDG
        assertEq(_payout(9_160_000), 34 * USDG);
    }

    function test_exactlyMaxCover() public view {
        assertEq(m.gapBps(FRIDAY, 9_000_000), 1000);
        assertEq(_payout(9_000_000), 50 * USDG);
    }

    function test_beyondMaxCover() public view {
        // -12% demo scenario and a total wipe-out both pay the cap
        assertEq(_payout(8_800_000), 50 * USDG);
        assertEq(_payout(0), 50 * USDG);
        assertEq(m.gapBps(FRIDAY, 0), 10_000);
    }

    function test_payoutNeverExceedsMaxPayout() public view {
        uint256 cap = m.maxPayout(N, C);
        assertEq(cap, 50 * USDG);
        for (uint256 open = 0; open <= FRIDAY; open += 50_000) {
            assertLe(_payout(open), cap);
        }
    }

    function test_gapRoundsDown() public view {
        // (3 - 2) * 10_000 / 3 = 3333.33 -> 3333
        assertEq(m.gapBps(3, 2), 3333);
        // 100.00000 -> 94.99999 is a 5.00001% gap -> floors to exactly the trigger -> no payout
        assertEq(m.gapBps(FRIDAY, 9_499_999), 500);
        assertEq(_payout(9_499_999), 0);
    }

    function test_payoutRoundsDown() public view {
        assertEq(m.payout(1, 1), 0); // 0.0001 -> 0
        assertEq(m.payout(19_999, 1), 1); // 1.9999 -> 1
        assertEq(m.maxPayout(19_999, 1), 1);
    }

    function test_monotonicAfterTrigger() public view {
        uint256 previous;
        for (uint256 open = FRIDAY; open > 0; open -= 10_000) {
            uint256 p = _payout(open);
            assertGe(p, previous, "payout must not decrease as the gap widens");
            previous = p;
        }
    }

    function test_coveredBps_bounds() public view {
        assertEq(m.coveredBps(0, T, C), 0);
        assertEq(m.coveredBps(T, T, C), 0);
        assertEq(m.coveredBps(T + 1, T, C), 1);
        assertEq(m.coveredBps(T + C, T, C), C);
        assertEq(m.coveredBps(10_000, T, C), C);
    }

    function test_extremePricesDoNotOverflow() public view {
        uint256 huge = type(uint256).max / 3;
        assertEq(m.gapBps(huge, huge / 2), 5000);
        assertEq(m.gapBps(type(uint256).max, 0), 10_000);
        assertEq(m.payoutFor(N, type(uint256).max, 1, T, C), 50 * USDG);
    }

    function test_zeroClosePriceReverts() public {
        vm.expectRevert(PayoutMath.ZeroClosePrice.selector);
        m.gapBps(0, 1);
    }
}
