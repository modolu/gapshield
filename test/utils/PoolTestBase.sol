// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {ProtectionPool} from "../../contracts/ProtectionPool.sol";
import {ProtectionReceipt} from "../../contracts/ProtectionReceipt.sol";
import {MockUSDG} from "../../contracts/mocks/MockUSDG.sol";
import {StubReferenceOracle} from "./StubReferenceOracle.sol";

/// @notice Shared fixture: frozen Phase 0 economics and the "TSLA 2026-W40" demo epoch timestamps.
abstract contract PoolTestBase is Test {
    uint256 internal constant USDG = 1e6;

    bytes32 internal constant TSLA = keccak256("TSLA");
    bytes32 internal constant TSLA_FEED_ID = bytes32(uint256(1435));

    // docs/PHASE0_DECISIONS.md §8 (UTC unix seconds)
    uint64 internal constant SALE_CUTOFF = 1_790_970_900;
    uint64 internal constant CLOSE_WINDOW_START = 1_790_971_140;
    uint64 internal constant CLOSE_WINDOW_END = 1_790_971_200;
    uint64 internal constant OPEN_WINDOW_START = 1_791_207_000;
    uint64 internal constant OPEN_WINDOW_END = 1_791_207_060;
    uint64 internal constant SETTLEMENT_DEADLINE = 1_791_466_260;
    uint256 internal constant START_TIME = SALE_CUTOFF - 6 hours;

    // docs/PHASE0_DECISIONS.md §7
    uint16 internal constant TRIGGER_BPS = 500;
    uint16 internal constant MAX_COVER_BPS = 500;
    uint16 internal constant PREMIUM_BPS = 80;
    uint16 internal constant PROTOCOL_FEE_BPS = 1200;
    uint16 internal constant UTILIZATION_CAP_BPS = 5000;
    uint256 internal constant MIN_NOTIONAL = 10 * USDG;
    uint256 internal constant MAX_NOTIONAL = 10_000 * USDG;
    uint256 internal constant MAX_AGGREGATE_LIABILITY = 2500 * USDG;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal lp1 = makeAddr("lp1");
    address internal lp2 = makeAddr("lp2");
    address internal buyer1 = makeAddr("buyer1");
    address internal buyer2 = makeAddr("buyer2");

    MockUSDG internal usdg;
    StubReferenceOracle internal oracle;
    ProtectionPool internal pool;
    ProtectionReceipt internal receipt;

    function setUp() public virtual {
        vm.warp(START_TIME);
        usdg = new MockUSDG();
        oracle = new StubReferenceOracle();
        pool = new ProtectionPool(usdg, owner, UTILIZATION_CAP_BPS);
        receipt = pool.receipt();

        vm.prank(owner);
        pool.addAsset(TSLA, TSLA_FEED_ID, "TSLA", 5);
    }

    function _defaultConfig() internal view returns (ProtectionPool.EpochConfig memory) {
        return ProtectionPool.EpochConfig({
            assetId: TSLA,
            oracle: address(oracle),
            saleCutoff: SALE_CUTOFF,
            closeWindowStart: CLOSE_WINDOW_START,
            closeWindowEnd: CLOSE_WINDOW_END,
            openWindowStart: OPEN_WINDOW_START,
            openWindowEnd: OPEN_WINDOW_END,
            settlementDeadline: SETTLEMENT_DEADLINE,
            triggerBps: TRIGGER_BPS,
            maxCoverBps: MAX_COVER_BPS,
            premiumBps: PREMIUM_BPS,
            protocolFeeBps: PROTOCOL_FEE_BPS,
            minNotional: MIN_NOTIONAL,
            maxNotional: MAX_NOTIONAL,
            maxAggregateLiability: MAX_AGGREGATE_LIABILITY
        });
    }

    function _createEpoch(ProtectionPool.EpochConfig memory config) internal returns (uint256 epochId) {
        vm.prank(owner);
        epochId = pool.createEpoch(config);
    }

    function _createDefaultEpoch() internal returns (uint256) {
        return _createEpoch(_defaultConfig());
    }

    function _deposit(address lp, uint256 amount) internal returns (uint256 shares) {
        usdg.mint(lp, amount);
        vm.startPrank(lp);
        usdg.approve(address(pool), amount);
        shares = pool.deposit(amount, lp);
        vm.stopPrank();
    }

    function _fundBuyer(address buyer, uint256 amount) internal {
        usdg.mint(buyer, amount);
        vm.prank(buyer);
        usdg.approve(address(pool), type(uint256).max);
    }

    function _buy(address buyer, uint256 epochId, uint256 notional) internal returns (uint256 policyId) {
        (uint256 premium,) = pool.quote(epochId, notional);
        _fundBuyer(buyer, premium);
        vm.prank(buyer);
        policyId = pool.buyProtection(epochId, notional);
    }
}
