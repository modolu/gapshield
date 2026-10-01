// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {MathHarness} from "../utils/MathHarness.sol";

contract PremiumMathTest is Test {
    uint256 internal constant USDG = 1e6;
    MathHarness internal m;

    function setUp() public {
        m = new MathHarness();
    }

    function test_premium_exactForWorkedExample() public view {
        // Architecture §8: 1,000 USDG at 80 bps -> 8.00 USDG
        assertEq(m.premium(1000 * USDG, 80), 8 * USDG);
        assertEq(m.premium(10 * USDG, 80), 80_000); // 0.08 USDG at minimum notional
        assertEq(m.premium(10_000 * USDG, 80), 80 * USDG);
    }

    function test_premium_roundsUp() public view {
        // 123_456_789 * 77 / 10_000 = 950_617.2753 -> 950_618
        assertEq(m.premium(123_456_789, 77), 950_618);
        // 1 * 80 / 10_000 = 0.008 -> 1 (never zero for a nonzero premium)
        assertEq(m.premium(1, 80), 1);
        // Exact division does not round up
        assertEq(m.premium(10_000, 80), 80);
    }

    function test_premium_zeroNotionalIsZero() public view {
        assertEq(m.premium(0, 80), 0);
    }

    function test_protocolFee_twelvePercentOfPremium() public view {
        assertEq(m.protocolFee(8 * USDG, 1200), 960_000); // 0.96 USDG
        assertEq(8 * USDG - m.protocolFee(8 * USDG, 1200), 7_040_000); // 88% to LPs
    }

    function test_protocolFee_roundsDown() public view {
        assertEq(m.protocolFee(9, 1200), 1); // 1.08 -> 1
        assertEq(m.protocolFee(8, 1200), 0); // 0.96 -> 0
        assertEq(m.protocolFee(80_000, 1200), 9600); // exact
    }
}
