// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolEpochTest is PoolTestBase {
    function test_createEpoch_storesFrozenConfigAndOpens() public {
        uint256 epochId = _createDefaultEpoch();
        assertEq(epochId, 1);
        assertEq(pool.activeEpochId(), 1);
        assertEq(pool.nextEpochId(), 2);

        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(epochId);
        assertEq(c.assetId, TSLA);
        assertEq(c.oracle, address(oracle));
        assertEq(c.saleCutoff, SALE_CUTOFF);
        assertEq(c.settlementDeadline, SETTLEMENT_DEADLINE);
        assertEq(c.triggerBps, TRIGGER_BPS);
        assertEq(c.maxCoverBps, MAX_COVER_BPS);
        assertEq(c.premiumBps, PREMIUM_BPS);
        assertEq(c.protocolFeeBps, PROTOCOL_FEE_BPS);
        assertEq(c.minNotional, MIN_NOTIONAL);
        assertEq(c.maxNotional, MAX_NOTIONAL);
        assertEq(c.maxAggregateLiability, MAX_AGGREGATE_LIABILITY);

        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        assertEq(uint8(s.status), uint8(ProtectionPool.EpochStatus.Open));
        assertEq(s.soldNotional, 0);
        assertEq(s.soldLiability, 0);
        assertEq(s.premiumCollected, 0);
    }

    function test_createEpoch_emitsEvent() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        vm.expectEmit(address(pool));
        emit ProtectionPool.EpochCreated(1, TSLA, address(oracle), c);
        _createEpoch(c);
    }

    function test_onlyOneActiveEpoch() public {
        _createDefaultEpoch();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.EpochAlreadyActive.selector, 1));
        pool.createEpoch(_defaultConfig());
    }

    function test_onlyOneActiveEpoch_evenAfterCutoff() public {
        _createDefaultEpoch();
        vm.warp(SETTLEMENT_DEADLINE + 1);
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.saleCutoff = uint64(block.timestamp + 1 hours);
        c.closeWindowStart = c.saleCutoff + 4 minutes;
        c.closeWindowEnd = c.closeWindowStart + 1 minutes;
        c.openWindowStart = c.closeWindowEnd + 1 days;
        c.openWindowEnd = c.openWindowStart + 1 minutes;
        c.settlementDeadline = c.openWindowEnd + 3 days;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.EpochAlreadyActive.selector, 1));
        pool.createEpoch(c);
    }

    function test_configFrozenAfterPurchases() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 10_000 * USDG);
        bytes memory before = abi.encode(pool.getEpochConfig(epochId));
        _buy(buyer1, epochId, 1000 * USDG);
        _buy(buyer2, epochId, 500 * USDG);
        assertEq(abi.encode(pool.getEpochConfig(epochId)), before);
    }

    function test_assetTermsAreImmutable() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.AssetAlreadyExists.selector, TSLA));
        pool.addAsset(TSLA, bytes32(uint256(999)), "XXX", 8);
        ProtectionPool.Asset memory a = pool.getAsset(TSLA);
        assertEq(a.oracleFeedId, TSLA_FEED_ID);
        assertEq(a.priceDecimals, 5);
    }

    function test_onlyOwnerCreatesEpoch() public {
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer1));
        pool.createEpoch(_defaultConfig());
    }

    // --- time ordering -------------------------------------------------------

    function _expectInvalidTimes(ProtectionPool.EpochConfig memory c) internal {
        vm.prank(owner);
        vm.expectRevert(ProtectionPool.InvalidEpochTimes.selector);
        pool.createEpoch(c);
    }

    function test_invalidTimes_cutoffNotInFuture() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.saleCutoff = uint64(block.timestamp);
        _expectInvalidTimes(c);
    }

    function test_invalidTimes_cutoffAfterCloseWindowStart() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.saleCutoff = c.closeWindowStart + 1;
        _expectInvalidTimes(c);
    }

    function test_invalidTimes_emptyCloseWindow() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.closeWindowEnd = c.closeWindowStart;
        _expectInvalidTimes(c);
    }

    function test_invalidTimes_openWindowBeforeCloseWindowEnds() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.openWindowStart = c.closeWindowEnd - 1;
        _expectInvalidTimes(c);
    }

    function test_invalidTimes_emptyOpenWindow() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.openWindowEnd = c.openWindowStart;
        _expectInvalidTimes(c);
    }

    function test_invalidTimes_deadlineNotAfterOpenWindow() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.settlementDeadline = c.openWindowEnd;
        _expectInvalidTimes(c);
    }

    function test_validTimes_adjacentBoundariesAccepted() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.closeWindowStart = c.saleCutoff; // cutoff may equal close-window start
        c.openWindowStart = c.closeWindowEnd; // windows may touch
        _createEpoch(c);
    }

    // --- economics -----------------------------------------------------------

    function _expectInvalidEconomics(ProtectionPool.EpochConfig memory c) internal {
        vm.prank(owner);
        vm.expectRevert(ProtectionPool.InvalidEpochEconomics.selector);
        pool.createEpoch(c);
    }

    function test_invalidEconomics_zeroCover() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxCoverBps = 0;
        _expectInvalidEconomics(c);
    }

    function test_invalidEconomics_triggerPlusCoverAbove100Percent() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.triggerBps = 9600;
        c.maxCoverBps = 500;
        _expectInvalidEconomics(c);
    }

    function test_invalidEconomics_zeroPremium() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.premiumBps = 0;
        _expectInvalidEconomics(c);
    }

    function test_invalidEconomics_premiumAboveCover() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.premiumBps = c.maxCoverBps + 1;
        _expectInvalidEconomics(c);
    }

    function test_invalidEconomics_protocolFeeAbove100Percent() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.protocolFeeBps = 10_001;
        _expectInvalidEconomics(c);
    }

    function test_invalidEconomics_zeroAggregateLiability() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxAggregateLiability = 0;
        _expectInvalidEconomics(c);
    }

    function _expectInvalidNotional(ProtectionPool.EpochConfig memory c) internal {
        vm.prank(owner);
        vm.expectRevert(ProtectionPool.InvalidNotionalBounds.selector);
        pool.createEpoch(c);
    }

    function test_invalidNotional_zeroMin() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.minNotional = 0;
        _expectInvalidNotional(c);
    }

    function test_invalidNotional_maxBelowMin() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxNotional = c.minNotional - USDG;
        _expectInvalidNotional(c);
    }

    function test_invalidNotional_minNotWholeUSDG() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.minNotional = 10 * USDG + 1;
        _expectInvalidNotional(c);
    }

    function test_invalidNotional_maxNotWholeUSDG() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.maxNotional = 10_000 * USDG - 1;
        _expectInvalidNotional(c);
    }

    // --- asset and oracle ----------------------------------------------------

    function test_unknownAssetRejected() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.assetId = keccak256("AAPL");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.UnknownAsset.selector, c.assetId));
        pool.createEpoch(c);
    }

    function test_disabledAssetRejected() public {
        vm.prank(owner);
        pool.setAssetEnabled(TSLA, false);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.AssetDisabled.selector, TSLA));
        pool.createEpoch(_defaultConfig());
    }

    function test_oracleMustBeContract() public {
        ProtectionPool.EpochConfig memory c = _defaultConfig();
        c.oracle = makeAddr("eoa");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidOracle.selector, c.oracle));
        pool.createEpoch(c);

        c.oracle = address(0);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidOracle.selector, address(0)));
        pool.createEpoch(c);
    }

    function test_invalidAssetRegistrationRejected() public {
        vm.startPrank(owner);
        vm.expectRevert(ProtectionPool.InvalidAsset.selector);
        pool.addAsset(bytes32(0), TSLA_FEED_ID, "X", 5);
        vm.expectRevert(ProtectionPool.InvalidAsset.selector);
        pool.addAsset(keccak256("X"), bytes32(0), "X", 5);
        vm.expectRevert(ProtectionPool.InvalidAsset.selector);
        pool.addAsset(keccak256("X"), TSLA_FEED_ID, "", 5);
        vm.stopPrank();
    }

    function test_setAssetEnabled_unknownAssetRejected() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.UnknownAsset.selector, keccak256("AAPL")));
        pool.setAssetEnabled(keccak256("AAPL"), true);
    }
}
