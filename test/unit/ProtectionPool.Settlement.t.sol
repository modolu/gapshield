// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {MockReferenceOracle} from "../utils/MockReferenceOracle.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";
import {SnapshotOracle} from "../../contracts/oracles/SnapshotOracle.sol";

contract ProtectionPoolSettlementTest is PoolTestBase {
    uint256 internal constant P100 = 10_000_000; // 100.00000 USD at exponent -5
    uint256 internal epochId;

    function setUp() public override {
        super.setUp();
        epochId = _createDefaultEpoch();
        _deposit(lp1, 10_000 * USDG);
    }

    function _status() internal view returns (ProtectionPool.EpochStatus) {
        return pool.getEpochState(epochId).status;
    }

    // --- close -----------------------------------------------------------------

    function test_settleClose_valid() public {
        _buy(buyer1, epochId, 1000 * USDG);
        vm.warp(CLOSE_WINDOW_START + 30);
        bytes memory data = _snapshot(P100, CLOSE_WINDOW_START + 10);
        bytes32 id = abi.decode(data, (bytes32));
        bytes32 expectedEvidence =
            keccak256(abi.encode(block.chainid, address(oracle), id, TSLA_FEED_ID, P100, CLOSE_WINDOW_START + 10));

        vm.expectEmit(address(pool));
        emit ProtectionPool.CloseSettled(epochId, P100, CLOSE_WINDOW_START + 10, expectedEvidence);
        vm.prank(operator);
        pool.settleClose(epochId, data);

        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(uint8(s.status), uint8(ProtectionPool.EpochStatus.CloseRecorded));
        assertEq(s.closePrice, P100);
        assertEq(s.closeTime, CLOSE_WINDOW_START + 10);
        assertEq(s.closeEvidence, expectedEvidence);
        assertEq(pool.reservedLiability(), 50 * USDG, "close does not touch accounting");
    }

    function test_settleClose_twiceRejected() public {
        _settleClose(epochId, P100);
        vm.warp(CLOSE_WINDOW_START + 1);
        bytes memory data = _snapshot(P100 + 1, CLOSE_WINDOW_START + 1);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.CloseRecorded
            )
        );
        pool.settleClose(epochId, data);
        assertEq(pool.getEpochState(epochId).closePrice, P100, "close reference unchanged");
    }

    function test_settleClose_onlyOperator() public {
        vm.warp(CLOSE_WINDOW_START);
        bytes memory data = _snapshot(P100, CLOSE_WINDOW_START);
        address[3] memory callers = [owner, buyer1, lp1];
        for (uint256 i; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(ProtectionPool.NotSettlementOperator.selector, callers[i]));
            pool.settleClose(epochId, data);
        }
    }

    function test_settleClose_unknownEpochRejected() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.InvalidEpochStatus.selector, 9, ProtectionPool.EpochStatus.None)
        );
        pool.settleClose(9, "");
    }

    // --- open ------------------------------------------------------------------

    function test_settleOpen_validAfterClose() public {
        _settleClose(epochId, P100);
        vm.warp(OPEN_WINDOW_START + 5);
        bytes memory data = _snapshot(9_800_000, OPEN_WINDOW_START + 5);
        vm.prank(operator);
        pool.settleOpen(epochId, data);
        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(uint8(s.status), uint8(ProtectionPool.EpochStatus.Settled));
        assertEq(s.openPrice, 9_800_000);
        assertEq(s.openTime, OPEN_WINDOW_START + 5);
        assertEq(s.gapBps, 200);
        assertEq(s.coveredBps, 0);
        assertTrue(s.openEvidence != bytes32(0) && s.openEvidence != s.closeEvidence);
    }

    function test_settleOpen_beforeCloseRejected() public {
        vm.warp(OPEN_WINDOW_START);
        bytes memory data = _snapshot(P100, OPEN_WINDOW_START);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.Open)
        );
        pool.settleOpen(epochId, data);
    }

    function test_settleOpen_twiceRejected() public {
        _settle(epochId, P100, 9_100_000);
        vm.warp(OPEN_WINDOW_START + 1);
        bytes memory data = _snapshot(5_000_000, OPEN_WINDOW_START + 1);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtectionPool.InvalidEpochStatus.selector, epochId, ProtectionPool.EpochStatus.Settled
            )
        );
        pool.settleOpen(epochId, data);
        assertEq(pool.getEpochState(epochId).openPrice, 9_100_000, "open reference unchanged");
    }

    function test_settleOpen_onlyOperator() public {
        _settleClose(epochId, P100);
        vm.warp(OPEN_WINDOW_START);
        bytes memory data = _snapshot(P100, OPEN_WINDOW_START);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.NotSettlementOperator.selector, owner));
        pool.settleOpen(epochId, data);
    }

    // --- oracle evidence checks ---------------------------------------------------

    function test_wrongFeedRejected() public {
        vm.warp(CLOSE_WINDOW_START);
        bytes32 otherFeed = bytes32(uint256(922));
        vm.prank(owner);
        bytes32 id = oracle.postSnapshot(otherFeed, P100, CLOSE_WINDOW_START);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.FeedMismatch.selector, TSLA_FEED_ID, otherFeed));
        pool.settleClose(epochId, abi.encode(id));
    }

    function test_snapshotFromAnotherOracleRejected() public {
        // The epoch's oracle is frozen; evidence posted to a different SnapshotOracle is unknown to it.
        SnapshotOracle rogue = new SnapshotOracle(buyer1);
        vm.warp(CLOSE_WINDOW_START);
        vm.prank(buyer1);
        bytes32 id = rogue.postSnapshot(TSLA_FEED_ID, 1, CLOSE_WINDOW_START);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.UnknownSnapshot.selector, id));
        pool.settleClose(epochId, abi.encode(id));
    }

    function test_timestampBeforeWindowRejected() public {
        vm.warp(CLOSE_WINDOW_START);
        bytes memory data = _snapshot(P100, CLOSE_WINDOW_START - 1);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SnapshotOracle.OutsideWindow.selector, CLOSE_WINDOW_START - 1, CLOSE_WINDOW_START, CLOSE_WINDOW_END
            )
        );
        pool.settleClose(epochId, data);
    }

    function test_timestampAfterWindowRejected() public {
        vm.warp(CLOSE_WINDOW_END + 10);
        bytes memory data = _snapshot(P100, CLOSE_WINDOW_END); // window is half-open
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SnapshotOracle.OutsideWindow.selector, CLOSE_WINDOW_END, CLOSE_WINDOW_START, CLOSE_WINDOW_END
            )
        );
        pool.settleClose(epochId, data);
    }

    function test_zeroPriceCannotBePosted() public {
        vm.warp(CLOSE_WINDOW_START);
        vm.prank(owner);
        vm.expectRevert(SnapshotOracle.ZeroPrice.selector);
        oracle.postSnapshot(TSLA_FEED_ID, 0, CLOSE_WINDOW_START);
    }

    // --- pool's own re-checks against a faulty adapter ------------------------------

    function _epochWithMockOracle() internal returns (uint256 id, MockReferenceOracle mock) {
        // Settle the default epoch first so a new one can open.
        _settle(epochId, P100, P100);
        mock = new MockReferenceOracle();
        ProtectionPool.EpochConfig memory c = _shiftedConfig(7 days);
        c.oracle = address(mock);
        id = _createEpoch(c);
    }

    function test_poolRejectsZeroPriceFromAdapter() public {
        (uint256 id, MockReferenceOracle mock) = _epochWithMockOracle();
        vm.warp(CLOSE_WINDOW_START + 7 days);
        mock.set(0, CLOSE_WINDOW_START + 7 days, bytes32("e"));
        vm.prank(operator);
        vm.expectRevert(ProtectionPool.InvalidReferencePrice.selector);
        pool.settleClose(id, "");
    }

    function test_poolRejectsOutOfWindowTimeFromAdapter() public {
        (uint256 id, MockReferenceOracle mock) = _epochWithMockOracle();
        uint64 start = CLOSE_WINDOW_START + 7 days;
        uint64 end = CLOSE_WINDOW_END + 7 days;
        vm.warp(end + 100);
        uint64[3] memory bad = [start - 1, end, end + 50];
        for (uint256 i; i < bad.length; ++i) {
            mock.set(P100, bad[i], bytes32("e"));
            vm.prank(operator);
            vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidReferenceTime.selector, bad[i], start, end));
            pool.settleClose(id, "");
        }
    }

    function test_poolRejectsFutureReferenceFromAdapter() public {
        (uint256 id, MockReferenceOracle mock) = _epochWithMockOracle();
        uint64 start = CLOSE_WINDOW_START + 7 days;
        vm.warp(start); // reference at start + 30 is still in the future
        mock.set(P100, start + 30, bytes32("e"));
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.InvalidReferenceTime.selector, start + 30, start, start + 60)
        );
        pool.settleClose(id, "");
    }

    function test_settlementForwardsFeeToAdapter() public {
        (uint256 id, MockReferenceOracle mock) = _epochWithMockOracle();
        vm.warp(CLOSE_WINDOW_START + 7 days);
        mock.set(P100, CLOSE_WINDOW_START + 7 days, bytes32("e"));
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        pool.settleClose{value: 1}(id, "");
        assertEq(mock.lastValue(), 1, "verification fee forwarded (Pyth-style adapters)");
        assertEq(address(pool).balance, 0, "pool keeps no ETH");
    }

    function test_snapshotOracleRejectsFeeThroughPool() public {
        vm.warp(CLOSE_WINDOW_START);
        bytes memory data = _snapshot(P100, CLOSE_WINDOW_START);
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        vm.expectRevert(SnapshotOracle.FeeNotAccepted.selector);
        pool.settleClose{value: 1}(epochId, data);
    }

    // --- deadline boundary -------------------------------------------------------

    function test_settlementBeforeDeadlineAllowed() public {
        _settleClose(epochId, P100);
        vm.warp(OPEN_WINDOW_START);
        bytes memory data = _snapshot(P100, OPEN_WINDOW_START);
        vm.warp(SETTLEMENT_DEADLINE - 1);
        vm.prank(operator);
        pool.settleOpen(epochId, data);
        assertEq(uint8(_status()), uint8(ProtectionPool.EpochStatus.Settled));
    }

    function test_settlementExactlyAtDeadlineRejected() public {
        _settleClose(epochId, P100);
        vm.warp(OPEN_WINDOW_START);
        bytes memory data = _snapshot(P100, OPEN_WINDOW_START);
        vm.warp(SETTLEMENT_DEADLINE);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.SettlementDeadlinePassed.selector, epochId, SETTLEMENT_DEADLINE)
        );
        pool.settleOpen(epochId, data);
    }

    function test_settlementAfterDeadlineRejected() public {
        vm.warp(CLOSE_WINDOW_START);
        bytes memory data = _snapshot(P100, CLOSE_WINDOW_START);
        vm.warp(SETTLEMENT_DEADLINE + 1 days);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ProtectionPool.SettlementDeadlinePassed.selector, epochId, SETTLEMENT_DEADLINE)
        );
        pool.settleClose(epochId, data);
    }

    function test_pauseDoesNotBlockSettlement() public {
        _buy(buyer1, epochId, 1000 * USDG);
        vm.prank(owner);
        pool.pause();
        _settle(epochId, P100, 9_100_000);
        assertEq(uint8(_status()), uint8(ProtectionPool.EpochStatus.Settled));
        assertEq(pool.claimablePayouts(), 40 * USDG);
    }

    function test_closeCannotPrecedeSaleCutoff() public {
        // Close window starts at the cutoff and references can't be in the future, so sales are always
        // closed before a close reference can exist.
        vm.warp(SALE_CUTOFF - 1);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(SnapshotOracle.FutureReferenceTime.selector, CLOSE_WINDOW_START, SALE_CUTOFF - 1)
        );
        oracle.postSnapshot(TSLA_FEED_ID, P100, CLOSE_WINDOW_START);
    }

    // --- successful settlement accounting (P7) ------------------------------------

    function test_calmWeekend_zeroActualOwed() public {
        _buy(buyer1, epochId, 1000 * USDG);
        _settle(epochId, P100, 9_800_000);
        assertEq(pool.claimablePayouts(), 0);
        assertEq(pool.reservedLiability(), 0);
        assertEq(pool.totalAssets(), 10_000 * USDG + 7_040_000); // + 88% of 8 USDG premium
    }

    function test_triggerBoundary_zeroActualOwed() public {
        _buy(buyer1, epochId, 1000 * USDG);
        _settle(epochId, P100, 9_500_000); // gap exactly 5.00%
        assertEq(pool.getEpochState(epochId).gapBps, 500);
        assertEq(pool.getEpochState(epochId).coveredBps, 0);
        assertEq(pool.claimablePayouts(), 0);
    }

    function test_triggeredPayout() public {
        _buy(buyer1, epochId, 1000 * USDG);
        _settle(epochId, P100, 9_100_000);
        assertEq(pool.getEpochState(epochId).coveredBps, 400);
        assertEq(pool.claimablePayouts(), 40 * USDG);
    }

    function test_maxCoverPayoutCapped() public {
        _buy(buyer1, epochId, 1000 * USDG);
        _settle(epochId, P100, 7_000_000); // 30% gap
        assertEq(pool.getEpochState(epochId).gapBps, 3000);
        assertEq(pool.getEpochState(epochId).coveredBps, 500);
        assertEq(pool.claimablePayouts(), 50 * USDG);
    }

    function test_settlementAccounting_exactP7Movements() public {
        _buy(buyer1, epochId, 1000 * USDG);
        _buy(buyer2, epochId, 3000 * USDG);
        // soldNotional 4,000; soldLiability 200; premium 32
        uint256 lpBefore = pool.totalAssets();
        uint256 balanceBefore = usdg.balanceOf(address(pool));
        assertEq(pool.reservedLiability(), 200 * USDG);
        assertEq(pool.pendingPremium(), 32 * USDG);

        _settleClose(epochId, P100);
        vm.warp(OPEN_WINDOW_START);
        bytes memory data = _snapshot(9_100_000, OPEN_WINDOW_START);
        vm.expectEmit(address(pool));
        emit ProtectionPool.EpochSettled(epochId, 900, 400, 160 * USDG, 3_840_000, 28_160_000);
        vm.prank(operator);
        pool.settleOpen(epochId, data);

        uint256 actualOwed = 160 * USDG; // 4% of 4,000
        uint256 fee = 3_840_000; // 12% of 32 = 3.84
        assertEq(pool.reservedLiability(), 0, "full epoch soldLiability released");
        assertEq(pool.claimablePayouts(), actualOwed);
        assertEq(pool.pendingPremium(), 0);
        assertEq(pool.protocolFeesAccrued(), fee);
        assertEq(pool.totalAssets(), lpBefore - actualOwed + (32 * USDG - fee));
        assertEq(usdg.balanceOf(address(pool)), balanceBefore, "settlement moves no tokens");
        assertEq(
            usdg.balanceOf(address(pool)),
            pool.totalAssets() + pool.pendingPremium() + pool.claimablePayouts() + pool.protocolFeesAccrued()
        );
    }

    function test_protocolFeeRoundsDown() public {
        // Odd fee bps so the 12%-style split does not divide evenly.
        ProtectionPool.EpochConfig memory c = _shiftedConfig(0);
        c.premiumBps = 77;
        c.protocolFeeBps = 1111;
        _settle(epochId, P100, P100);
        uint256 id = _createEpoch(_shift(c, 7 days));
        _buy(buyer1, id, 13 * USDG); // premium ceil(13e6 * 77 / 1e4) = 100_100
        _settle(id, P100, P100);
        // fee = floor(100_100 * 1_111 / 10_000) = floor(11_121.11) = 11_121
        assertEq(pool.protocolFeesAccrued(), 11_121);
    }

    function test_laterSettlementCannotConsumeEarlierVoidRefundEscrow() public {
        _buy(buyer1, epochId, 1000 * USDG); // premium 8 escrowed
        vm.warp(SETTLEMENT_DEADLINE);
        pool.voidEpoch(epochId);
        assertEq(pool.pendingPremium(), 8 * USDG);

        uint256 id2 = _createEpoch(_shiftedConfig(7 days));
        uint256 p2 = _buy(buyer2, id2, 2000 * USDG); // premium 16
        assertEq(pool.pendingPremium(), 24 * USDG);
        _settle(id2, P100, 9_100_000);

        assertEq(pool.pendingPremium(), 8 * USDG, "only epoch 2's premium left escrow");
        assertEq(_claim(buyer1, 1), 8 * USDG, "epoch 1 refund still fully available");
        assertEq(pool.pendingPremium(), 0);
        assertEq(_claim(buyer2, p2), 80 * USDG);
        assertEq(pool.claimablePayouts(), 0);
    }

    function test_claimablePayoutsDoNotIncreaseSellingCapacity() public {
        _buy(buyer1, epochId, 10_000 * USDG); // reserve 500
        _settle(epochId, P100, 5_000_000); // max payout: 500 owed
        uint256 lpAssets = pool.totalAssets(); // 10,000 - 500 + 70.40
        assertEq(pool.claimablePayouts(), 500 * USDG);
        assertEq(pool.freeCollateral(), lpAssets, "claimable payouts are not free collateral");

        ProtectionPool.EpochConfig memory c = _shiftedConfig(7 days);
        c.maxAggregateLiability = 1_000_000 * USDG;
        c.maxNotional = 1_000_000 * USDG;
        uint256 id2 = _createEpoch(c);
        uint256 capacity = lpAssets * UTILIZATION_CAP_BPS / 10_000;
        // Largest whole-USDG notional whose 5% reserve fits in capacity:
        uint256 notional = (capacity * 20) / USDG * USDG;
        _buy(buyer2, id2, notional);
        _fundBuyer(buyer2, 10 * USDG);
        vm.prank(buyer2);
        vm.expectRevert();
        pool.buyProtection(id2, 20 * USDG);
        assertLe(pool.reservedLiability(), capacity);
    }

    function _shift(ProtectionPool.EpochConfig memory c, uint64 offset)
        internal
        pure
        returns (ProtectionPool.EpochConfig memory)
    {
        c.saleCutoff += offset;
        c.closeWindowStart += offset;
        c.closeWindowEnd += offset;
        c.openWindowStart += offset;
        c.openWindowEnd += offset;
        c.settlementDeadline += offset;
        return c;
    }
}
