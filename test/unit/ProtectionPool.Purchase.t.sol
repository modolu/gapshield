// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolPurchaseTest is PoolTestBase {
    uint256 internal epochId;

    function setUp() public override {
        super.setUp();
        epochId = _createDefaultEpoch();
        _deposit(lp1, 10_000 * USDG); // utilization capacity: 5,000 USDG of reserve
    }

    // --- premium / notional --------------------------------------------------

    function test_buy_workedExample() public {
        uint256 policyId = _buy(buyer1, epochId, 1000 * USDG);
        ProtectionPool.Policy memory p = pool.getPolicy(policyId);
        assertEq(policyId, 1);
        assertEq(p.epochId, epochId);
        assertEq(p.notional, 1000 * USDG);
        assertEq(p.premiumUSDG, 8 * USDG);
        assertEq(p.maxPayout, 50 * USDG);
        assertFalse(p.claimed);
        assertEq(usdg.balanceOf(buyer1), 0, "buyer paid exactly the quoted premium");
    }

    function test_buy_emitsEvent() public {
        _fundBuyer(buyer1, 8 * USDG);
        vm.expectEmit(address(pool));
        emit ProtectionPool.ProtectionPurchased(1, epochId, buyer1, 1000 * USDG, 8 * USDG, 50 * USDG);
        vm.prank(buyer1);
        pool.buyProtection(epochId, 1000 * USDG);
    }

    function test_minNotional() public {
        _buy(buyer1, epochId, MIN_NOTIONAL);
        _fundBuyer(buyer1, 1 * USDG);
        vm.prank(buyer1);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.NotionalOutOfRange.selector, 9 * USDG, MIN_NOTIONAL, MAX_NOTIONAL)
        );
        pool.buyProtection(epochId, 9 * USDG);
    }

    function test_maxNotional() public {
        _buy(buyer1, epochId, MAX_NOTIONAL);
        _fundBuyer(buyer1, 100 * USDG);
        vm.prank(buyer1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtectionPool.NotionalOutOfRange.selector, MAX_NOTIONAL + USDG, MIN_NOTIONAL, MAX_NOTIONAL
            )
        );
        pool.buyProtection(epochId, MAX_NOTIONAL + USDG);
    }

    function test_nonWholeUSDGNotionalRejected() public {
        _fundBuyer(buyer1, 100 * USDG);
        uint256[3] memory bad = [uint256(10 * USDG + 500_000), 1000 * USDG + 1, 9999 * USDG + 999_999];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(buyer1);
            vm.expectRevert(abi.encodeWithSelector(ProtectionPool.NotionalNotWholeUSDG.selector, bad[i]));
            pool.buyProtection(epochId, bad[i]);
        }
    }

    function test_quoteMatchesPurchase() public {
        (uint256 premium, uint256 maxPayout) = pool.quote(epochId, 2345 * USDG);
        uint256 policyId = _buy(buyer1, epochId, 2345 * USDG);
        assertEq(pool.getPolicy(policyId).premiumUSDG, premium);
        assertEq(pool.getPolicy(policyId).maxPayout, maxPayout);
        assertEq(premium, 18_760_000); // 18.76 USDG
        assertEq(maxPayout, 117_250_000); // 117.25 USDG
    }

    function test_quote_unknownEpochReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidEpoch.selector, 99));
        pool.quote(99, 1000 * USDG);
    }

    // --- cutoff --------------------------------------------------------------

    function test_purchaseBeforeCutoffWorks() public {
        vm.warp(SALE_CUTOFF - 1);
        _buy(buyer1, epochId, 100 * USDG);
    }

    function test_purchaseAtCutoffFails() public {
        _fundBuyer(buyer1, 100 * USDG);
        vm.warp(SALE_CUTOFF);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.SaleClosed.selector, epochId));
        pool.buyProtection(epochId, 100 * USDG);
    }

    function test_purchaseAfterCutoffFails() public {
        _fundBuyer(buyer1, 100 * USDG);
        vm.warp(SALE_CUTOFF + 1 days);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.SaleClosed.selector, epochId));
        pool.buyProtection(epochId, 100 * USDG);
    }

    function test_purchaseOnUnknownEpochFails() public {
        _fundBuyer(buyer1, 100 * USDG);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidEpoch.selector, 2));
        pool.buyProtection(2, 100 * USDG);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidEpoch.selector, 0));
        pool.buyProtection(0, 100 * USDG);
    }

    function test_purchaseWithoutPremiumFundsReverts() public {
        vm.prank(buyer1);
        vm.expectRevert(); // ERC20InsufficientAllowance
        pool.buyProtection(epochId, 100 * USDG);
        assertEq(pool.reservedLiability(), 0, "failed purchase reserved nothing");
        assertEq(pool.nextPolicyId(), 1);
    }

    // --- solvency ------------------------------------------------------------

    function test_reservedLiabilityIncreasesExactlyOnPurchase() public {
        uint256 before = pool.reservedLiability();
        _buy(buyer1, epochId, 1234 * USDG);
        assertEq(pool.reservedLiability() - before, 61_700_000); // 5% of 1,234 = 61.70 USDG
    }

    function test_premiumDoesNotBecomeLpCapitalOnPurchase() public {
        uint256 assetsBefore = pool.totalAssets();
        uint256 shareValueBefore = pool.convertToAssets(pool.balanceOf(lp1));
        _buy(buyer1, epochId, 1000 * USDG);
        assertEq(pool.totalAssets(), assetsBefore, "totalAssets excludes escrowed premium");
        assertEq(pool.convertToAssets(pool.balanceOf(lp1)), shareValueBefore, "share value unchanged");
        assertEq(pool.pendingPremium(), 8 * USDG);
        assertEq(pool.getEpochState(epochId).premiumCollected, 8 * USDG);
        assertEq(pool.protocolFeesAccrued(), 0);
        assertEq(usdg.balanceOf(address(pool)), 10_000 * USDG + 8 * USDG);
    }

    function test_cannotOversellCollateral() public {
        // Pool holds 10,000 USDG; utilization cap allows 5,000 USDG of reserve.
        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(epochId);
        assertEq(c.maxAggregateLiability, 2500 * USDG);
        // Epoch aggregate cap binds first here: 5 x 10,000 notional = 2,500 reserve.
        for (uint256 i; i < 5; ++i) {
            _buy(buyer1, epochId, MAX_NOTIONAL);
        }
        assertEq(pool.reservedLiability(), 2500 * USDG);
        _fundBuyer(buyer1, 1 * USDG);
        vm.prank(buyer1);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.EpochCapacityExceeded.selector, 2500 * USDG + 500_000, 2500 * USDG)
        );
        pool.buyProtection(epochId, MIN_NOTIONAL);
    }

    function test_utilizationCapEnforcedAtExactBoundary() public {
        // Fresh pool with 1,000 USDG -> capacity 500 USDG reserve = 10,000 USDG notional.
        ProtectionPool small = _freshPoolWithEpoch(1000 * USDG, 1_000_000 * USDG);
        _fundBuyer(buyer1, 1000 * USDG);
        vm.startPrank(buyer1);
        usdg.approve(address(small), type(uint256).max);
        small.buyProtection(1, 10_000 * USDG); // reserve 500 == capacity
        assertEq(small.reservedLiability(), 500 * USDG);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.PoolCapacityExceeded.selector, 500 * USDG + 500_000, 500 * USDG)
        );
        small.buyProtection(1, MIN_NOTIONAL);
        vm.stopPrank();
    }

    function test_epochAggregateLiabilityCapEnforced() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxAggregateLiability = 100 * USDG;
        ProtectionPool p = _freshPoolWithConfig(1_000_000 * USDG, c);
        _fundBuyer(buyer1, 1000 * USDG);
        vm.startPrank(buyer1);
        usdg.approve(address(p), type(uint256).max);
        p.buyProtection(1, 2000 * USDG); // liability 100 == cap
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.EpochCapacityExceeded.selector, 100 * USDG + 500_000, 100 * USDG)
        );
        p.buyProtection(1, MIN_NOTIONAL);
        vm.stopPrank();
    }

    function test_purchasesCannotUseEscrowedPremiumAsCollateral() public {
        // 1,000 USDG LP capital -> 500 USDG reserve capacity. Fill it; the 80 USDG of escrowed
        // premium now sitting in the pool must not create any additional capacity.
        ProtectionPool p = _freshPoolWithEpoch(1000 * USDG, 1_000_000 * USDG);
        _fundBuyer(buyer1, 1000 * USDG);
        vm.startPrank(buyer1);
        usdg.approve(address(p), type(uint256).max);
        p.buyProtection(1, 10_000 * USDG);
        assertEq(p.pendingPremium(), 80 * USDG);
        assertEq(usdg.balanceOf(address(p)), 1080 * USDG);
        assertEq(p.totalAssets(), 1000 * USDG);
        assertEq(p.freeCollateral(), 500 * USDG);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.PoolCapacityExceeded.selector, 500 * USDG + 500_000, 500 * USDG)
        );
        p.buyProtection(1, MIN_NOTIONAL);
        vm.stopPrank();
    }

    function test_multiplePoliciesAggregateCorrectly() public {
        _buy(buyer1, epochId, 1000 * USDG);
        _buy(buyer2, epochId, 250 * USDG);
        _buy(buyer1, epochId, 3333 * USDG);

        uint256 notional = 4583 * USDG;
        uint256 liability = 229_150_000; // 5% of 4,583
        uint256 premium = 36_664_000; // 0.8% of 4,583

        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(s.soldNotional, notional);
        assertEq(s.soldLiability, liability);
        assertEq(s.premiumCollected, premium);
        assertTrue(s.soldNotional != s.soldLiability, "notional and liability are distinct quantities");
        assertEq(pool.reservedLiability(), liability);
        assertEq(pool.pendingPremium(), premium);
        assertEq(pool.nextPolicyId(), 4);
        assertEq(receipt.ownerOf(1), buyer1);
        assertEq(receipt.ownerOf(2), buyer2);
        assertEq(receipt.ownerOf(3), buyer1);
    }

    function test_previewPayoutAt_usesPolicyTerms() public {
        uint256 policyId = _buy(buyer1, epochId, 1000 * USDG);
        assertEq(pool.previewPayoutAt(policyId, 10_000_000, 9_100_000), 40 * USDG);
        assertEq(pool.previewPayoutAt(policyId, 10_000_000, 8_800_000), 50 * USDG);
        assertEq(pool.previewPayoutAt(policyId, 10_000_000, 9_600_000), 0);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.UnknownPolicy.selector, 99));
        pool.previewPayoutAt(99, 100, 90);
    }

    // --- helpers ---------------------------------------------------------------

    function _freshPoolWithEpoch(uint256 lpCapital, uint256 maxAggregate) internal returns (ProtectionPool) {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxAggregateLiability = maxAggregate;
        return _freshPoolWithConfig(lpCapital, c);
    }

    function _freshPoolWithConfig(uint256 lpCapital, ProtectionPool.EpochConfig memory c)
        internal
        returns (ProtectionPool p)
    {
        p = new ProtectionPool(usdg, owner, UTILIZATION_CAP_BPS);
        vm.startPrank(owner);
        p.addAsset(TSLA, TSLA_FEED_ID, "TSLA", 5);
        p.createEpoch(c);
        vm.stopPrank();
        usdg.mint(lp2, lpCapital);
        vm.startPrank(lp2);
        usdg.approve(address(p), lpCapital);
        p.deposit(lpCapital, lp2);
        vm.stopPrank();
    }
}
