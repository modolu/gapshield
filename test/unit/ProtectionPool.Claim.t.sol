// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolClaimTest is PoolTestBase {
    uint256 internal constant P100 = 10_000_000;
    uint256 internal epochId;
    uint256 internal p1; // buyer1, 1,000 USDG
    uint256 internal p2; // buyer2, 2,500 USDG

    function setUp() public override {
        super.setUp();
        epochId = _createDefaultEpoch();
        _deposit(lp1, 10_000 * USDG);
        p1 = _buy(buyer1, epochId, 1000 * USDG);
        p2 = _buy(buyer2, epochId, 2500 * USDG);
    }

    function test_ownerCanClaim() public {
        _settle(epochId, P100, 9_100_000); // 4% covered
        vm.expectEmit(address(pool));
        emit ProtectionPool.ProtectionClaimed(p1, epochId, buyer1, 40 * USDG);
        assertEq(_claim(buyer1, p1), 40 * USDG);
        assertEq(usdg.balanceOf(buyer1), 40 * USDG);
        assertTrue(pool.getPolicy(p1).claimed);
    }

    function test_nonOwnerCannotClaim() public {
        _settle(epochId, P100, 9_100_000);
        address[3] memory others = [buyer2, lp1, owner];
        for (uint256 i; i < others.length; ++i) {
            vm.prank(others[i]);
            vm.expectRevert(abi.encodeWithSelector(ProtectionPool.NotPolicyOwner.selector, p1, others[i]));
            pool.claim(p1);
        }
    }

    function test_cannotClaimTwice() public {
        _settle(epochId, P100, 9_100_000);
        _claim(buyer1, p1);
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.PolicyAlreadyClaimed.selector, p1));
        pool.claim(p1);
        assertEq(usdg.balanceOf(buyer1), 40 * USDG);
    }

    function test_zeroPayoutPolicyFinalizesExactlyOnce() public {
        _settle(epochId, P100, 9_800_000); // calm
        uint256 claimableBefore = pool.claimablePayouts();
        uint256 balanceBefore = usdg.balanceOf(address(pool));
        vm.expectEmit(address(pool));
        emit ProtectionPool.ProtectionClaimed(p1, epochId, buyer1, 0);
        assertEq(_claim(buyer1, p1), 0);
        assertTrue(pool.getPolicy(p1).claimed);
        assertEq(pool.claimablePayouts(), claimableBefore);
        assertEq(usdg.balanceOf(address(pool)), balanceBefore, "nothing transferred");
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.PolicyAlreadyClaimed.selector, p1));
        pool.claim(p1);
    }

    function test_positiveClaimDecreasesClaimableExactly() public {
        _settle(epochId, P100, 9_100_000);
        assertEq(pool.claimablePayouts(), 140 * USDG); // 4% of 3,500
        _claim(buyer2, p2);
        assertEq(pool.claimablePayouts(), 40 * USDG);
    }

    function test_claimableDrainsToZeroWhenAllClaim() public {
        _settle(epochId, P100, 9_233_333); // gap 7.66667% -> 766 bps -> covered 266
        uint256 owed = pool.claimablePayouts();
        uint256 a = _claim(buyer2, p2);
        uint256 b = _claim(buyer1, p1);
        assertEq(a + b, owed);
        assertEq(pool.claimablePayouts(), 0);
    }

    function test_claimWorksWhilePaused() public {
        _settle(epochId, P100, 9_100_000);
        vm.prank(owner);
        pool.pause();
        assertEq(_claim(buyer1, p1), 40 * USDG);
    }

    function test_claimedAmountNeverExceedsMaxPayout() public {
        _settle(epochId, P100, 1); // ~100% gap
        assertEq(_claim(buyer1, p1), pool.getPolicy(p1).maxPayout);
        assertEq(_claim(buyer2, p2), pool.getPolicy(p2).maxPayout);
    }

    function test_cannotClaimBeforeFinalization() public {
        vm.prank(buyer1);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.Open)
        );
        pool.claim(p1);
        _settleClose(epochId, P100);
        vm.prank(buyer1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.CloseRecorded
            )
        );
        pool.claim(p1);
    }

    function test_unknownPolicyRejected() public {
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.UnknownPolicy.selector, 99));
        pool.claim(99);
    }

    function test_previewPayout() public {
        assertEq(pool.previewPayout(p1), 0, "0 before settlement");
        _settle(epochId, P100, 9_100_000);
        assertEq(pool.previewPayout(p1), 40 * USDG);
        assertEq(pool.previewPayout(p2), 100 * USDG);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.UnknownPolicy.selector, 99));
        pool.previewPayout(99);
    }

    function test_lpCannotWithdrawClaimablePayouts() public {
        _settle(epochId, P100, 5_000_000); // max payouts: 175 owed
        assertEq(pool.claimablePayouts(), 175 * USDG);
        uint256 lpAssets = pool.totalAssets();
        assertEq(pool.maxWithdraw(lp1), lpAssets);
        vm.prank(lp1);
        pool.withdraw(lpAssets, lp1, lp1);
        // Every claim is still fully payable after the LP takes everything withdrawable.
        assertEq(_claim(buyer1, p1), 50 * USDG);
        assertEq(_claim(buyer2, p2), 125 * USDG);
        assertEq(pool.claimablePayouts(), 0);
        assertEq(usdg.balanceOf(address(pool)), pool.protocolFeesAccrued());
    }
}
