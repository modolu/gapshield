// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolVoidTest is PoolTestBase {
    uint256 internal constant P100 = 10_000_000;
    uint256 internal epochId;
    uint256 internal p1; // buyer1, 1,000 USDG: premium 8, reserve 50
    uint256 internal p2; // buyer2, 500 USDG: premium 4, reserve 25
    address internal stranger = makeAddr("stranger");

    function setUp() public override {
        super.setUp();
        epochId = _createDefaultEpoch();
        _deposit(lp1, 10_000 * USDG);
        p1 = _buy(buyer1, epochId, 1000 * USDG);
        p2 = _buy(buyer2, epochId, 500 * USDG);
    }

    function _void() internal {
        vm.prank(stranger);
        pool.voidEpoch(epochId);
    }

    function test_cannotVoidBeforeDeadline() public {
        vm.warp(SETTLEMENT_DEADLINE - 1);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.SettlementDeadlineNotReached.selector, epochId, SETTLEMENT_DEADLINE)
        );
        pool.voidEpoch(epochId);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.SettlementDeadlineNotReached.selector, epochId, SETTLEMENT_DEADLINE)
        );
        pool.voidEpoch(epochId); // no admin early void either
    }

    function test_canVoidExactlyAtDeadline_permissionless() public {
        vm.warp(SETTLEMENT_DEADLINE);
        vm.expectEmit(address(pool));
        emit ProtectionPool.EpochVoided(epochId, 75 * USDG, 12 * USDG);
        _void();
        assertEq(uint8(pool.getEpochState(epochId).status), uint8(ProtectionPool.EpochStatus.Voided));
    }

    function test_canVoidAfterCloseRecorded() public {
        _settleClose(epochId, P100); // open never arrives
        vm.warp(SETTLEMENT_DEADLINE + 1 days);
        _void();
        assertEq(uint8(pool.getEpochState(epochId).status), uint8(ProtectionPool.EpochStatus.Voided));
    }

    function test_cannotVoidSettledEpoch() public {
        _settle(epochId, P100, 9_100_000);
        vm.warp(SETTLEMENT_DEADLINE + 1);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.Settled
            )
        );
        pool.voidEpoch(epochId);
    }

    function test_cannotVoidTwice() public {
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.Voided
            )
        );
        pool.voidEpoch(epochId);
    }

    function test_cannotVoidUnknownEpoch() public {
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.InvalidEpochStatus.selector, 7, ProtectionPool.EpochStatus.None)
        );
        pool.voidEpoch(7);
    }

    function test_cannotSettleAfterVoid() public {
        vm.warp(CLOSE_WINDOW_START);
        bytes memory data = _snapshot(P100, CLOSE_WINDOW_START);
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.Voided
            )
        );
        pool.settleClose(epochId, data);
    }

    function test_voidReleasesFullReserveAndKeepsPremiumEscrowed() public {
        assertEq(pool.reservedLiability(), 75 * USDG);
        uint256 lpBefore = pool.totalAssets();
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        assertEq(pool.reservedLiability(), 0);
        assertEq(pool.pendingPremium(), 12 * USDG, "premium remains escrowed until refunds");
        assertEq(pool.totalAssets(), lpBefore, "LPs neither gain premium nor lose capital on void");
        assertEq(pool.claimablePayouts(), 0);
        assertEq(pool.protocolFeesAccrued(), 0);
        assertEq(pool.maxWithdraw(lp1), lpBefore, "LP capital unlocked");
    }

    function test_ownerCanRefund() public {
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        vm.expectEmit(address(pool));
        emit ProtectionPool.PremiumRefunded(p1, epochId, buyer1, 8 * USDG);
        assertEq(_claim(buyer1, p1), 8 * USDG);
        assertEq(usdg.balanceOf(buyer1), 8 * USDG);
    }

    function test_nonOwnerCannotRefund() public {
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        vm.prank(buyer2);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.NotPolicyOwner.selector, p1, buyer2));
        pool.claim(p1);
    }

    function test_refundOnlyOnce() public {
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        _claim(buyer1, p1);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.PolicyAlreadyClaimed.selector, p1));
        pool.claim(p1);
    }

    function test_refundDecreasesPendingPremiumExactly_neverClaimable() public {
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        _claim(buyer1, p1);
        assertEq(pool.pendingPremium(), 4 * USDG);
        assertEq(pool.claimablePayouts(), 0);
        _claim(buyer2, p2);
        assertEq(pool.pendingPremium(), 0, "voided epoch contributes nothing once all refunded");
        assertEq(pool.claimablePayouts(), 0);
    }

    function test_voidAndRefundWorkWhilePaused() public {
        vm.prank(owner);
        pool.pause();
        vm.warp(SETTLEMENT_DEADLINE);
        _void();
        assertEq(_claim(buyer1, p1), 8 * USDG);
    }
}
