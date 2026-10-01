// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {PoolHandler} from "./PoolHandler.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolInvariantTest is StdInvariant, PoolTestBase {
    PoolHandler internal handler;
    uint256 internal epochId;

    function setUp() public override {
        super.setUp();
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxAggregateLiability = 100_000 * USDG;
        epochId = _createEpoch(c);
        handler = new PoolHandler(pool, usdg, owner, epochId);
        targetContract(address(handler));
    }

    /// 1. reservedLiability <= claim-supporting collateral (LP-owned assets).
    function invariant_reservedLiabilityWithinClaimSupportingCollateral() public view {
        assertLe(pool.reservedLiability(), pool.totalAssets());
    }

    /// 2. LP withdrawal never reduces claim-supporting collateral below reservedLiability: no LP can ever be
    /// offered more than free collateral, and every reserve change is accounted for by purchases only.
    function invariant_withdrawalsBoundedByFreeCollateral() public view {
        assertEq(handler.ghostMaxWithdrawViolations(), 0);
        for (uint256 i; i < handler.lpCount(); ++i) {
            address lp = handler.lps(i);
            assertLe(pool.maxWithdraw(lp), pool.freeCollateral());
            assertLe(pool.previewRedeem(pool.maxRedeem(lp)), pool.freeCollateral());
        }
    }

    /// 3. Policy economics (incl. max payout) are immutable after purchase.
    function invariant_policyTermsImmutable() public view {
        for (uint256 i; i < handler.policyCount(); ++i) {
            uint256 policyId = handler.policyIds(i);
            ProtectionPool.Policy memory p = pool.getPolicy(policyId);
            assertEq(p.maxPayout, handler.ghostMaxPayout(policyId));
            assertEq(p.notional, handler.ghostNotional(policyId));
            assertEq(p.premiumUSDG, handler.ghostPremium(policyId));
            assertEq(p.epochId, epochId);
            assertFalse(p.claimed);
        }
    }

    /// 4. Aggregate sold liability never exceeds configured limits, and reserve equals what was sold.
    function invariant_aggregateLiabilityWithinLimits() public view {
        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(epochId);
        assertLe(s.soldLiability, c.maxAggregateLiability);
        assertEq(pool.reservedLiability(), s.soldLiability, "Phase 1: only one epoch reserves liability");
        uint256 sumMaxPayout;
        uint256 sumNotional;
        for (uint256 i; i < handler.policyCount(); ++i) {
            uint256 policyId = handler.policyIds(i);
            sumMaxPayout += handler.ghostMaxPayout(policyId);
            sumNotional += handler.ghostNotional(policyId);
        }
        assertEq(s.soldLiability, sumMaxPayout);
        assertEq(s.soldNotional, sumNotional);
    }

    /// 5. Escrowed premium is never counted as LP-owned capital before settlement.
    function invariant_escrowedPremiumNotLpCapital() public view {
        assertEq(pool.totalAssets(), handler.ghostLpDeposited() - handler.ghostLpWithdrawn());
        assertEq(pool.pendingPremium(), handler.ghostPremiums());
        assertEq(pool.getEpochState(epochId).premiumCollected, handler.ghostPremiums());
    }

    /// 6. Protocol fees are never counted as LP-owned capital; token balance covers every bucket exactly
    /// (plus untracked donations, which are never credited to anyone).
    function invariant_feesAndBalanceSegregated() public view {
        assertEq(pool.protocolFeesAccrued(), 0, "Phase 1: fees accrue only at settlement");
        assertEq(
            usdg.balanceOf(address(pool)),
            pool.totalAssets() + pool.pendingPremium() + pool.protocolFeesAccrued() + handler.ghostDonations()
        );
    }

    /// 7. Receipt ownership cannot change through transfer or approval.
    function invariant_receiptOwnershipFixed() public view {
        assertEq(handler.ghostReceiptTransferSuccesses(), 0);
        for (uint256 i; i < handler.policyCount(); ++i) {
            uint256 policyId = handler.policyIds(i);
            assertEq(receipt.ownerOf(policyId), handler.ghostOwner(policyId));
        }
        if (handler.policyCount() > 0) assertEq(receipt.getApproved(handler.policyIds(0)), address(0));
    }

    /// Every handler action matched the independent model (valid actions succeeded, invalid ones reverted).
    function invariant_handlerOutcomesMatchModel() public view {
        assertEq(handler.ghostUnexpected(), 0, handler.lastUnexpected());
    }
}
