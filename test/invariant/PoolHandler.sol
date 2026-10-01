// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ProtectionPool} from "../../contracts/ProtectionPool.sol";
import {ProtectionReceipt} from "../../contracts/ProtectionReceipt.sol";
import {SnapshotOracle} from "../../contracts/oracles/SnapshotOracle.sol";
import {MockUSDG} from "../../contracts/mocks/MockUSDG.sol";

/// @notice Drives the full lifecycle (epochs, LP flows, purchases, settlement, void, claims, refunds, fees,
/// pause, donations, receipt transfers) with bounded random inputs. Every action predicts its outcome from an
/// independent ghost model and records any mismatch in `ghostUnexpected`; the suite asserts it stays zero.
/// The model never consults `paused()` for settlement, void, claims or LP withdrawals, so any pause-induced
/// failure of those actions is caught as an unexpected outcome.
contract PoolHandler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant USDG = 1e6;
    uint256 internal constant BPS = 10_000;

    struct GhostEpoch {
        ProtectionPool.EpochStatus status;
        uint256 soldNotional;
        uint256 soldLiability;
        uint256 premiumCollected;
        uint16 coveredBps;
        bytes32 refsHash; // hash of recorded references once Settled
    }

    struct GhostPolicy {
        uint256 epochId;
        address owner;
        uint256 notional;
        uint256 premium;
        uint256 maxPayout;
        bool claimed;
        uint256 claimCount;
    }

    ProtectionPool public immutable pool;
    ProtectionReceipt public immutable receipt;
    SnapshotOracle public immutable oracle;
    MockUSDG public immutable usdg;
    address public immutable admin;
    address public immutable operator;
    bytes32 public immutable assetId;
    bytes32 public immutable feedId;

    address[] public lps;
    address[] public buyers;
    uint256[] public epochIds;
    uint256[] public policyIds;
    mapping(uint256 => GhostEpoch) internal _ghostEpochs;
    mapping(uint256 => GhostPolicy) internal _ghostPolicies;

    // Ghost buckets (independent model of the pool's accounting)
    uint256 public ghostLpAssets;
    uint256 public ghostReserved;
    uint256 public ghostPending;
    uint256 public ghostClaimable;
    uint256 public ghostFees;
    uint256 public ghostDonations;

    uint256 public ghostReceiptTransferSuccesses;
    uint256 public ghostUnexpected;
    string public lastUnexpected;
    mapping(bytes4 => uint256) public calls;
    uint256 public pausedLifecycleCalls; // settle/void/claim/withdraw attempted while paused
    mapping(bytes4 => uint256) public successes;
    uint256 public positiveClaims; // claims that paid a nonzero settled payout
    uint256 public pausedSuccesses; // lifecycle actions that succeeded while paused

    constructor(
        ProtectionPool pool_,
        SnapshotOracle oracle_,
        MockUSDG usdg_,
        address admin_,
        address operator_,
        bytes32 assetId_,
        bytes32 feedId_
    ) {
        pool = pool_;
        receipt = pool_.receipt();
        oracle = oracle_;
        usdg = usdg_;
        admin = admin_;
        operator = operator_;
        assetId = assetId_;
        feedId = feedId_;
        for (uint256 i; i < 3; ++i) {
            lps.push(makeAddr(string.concat("lp", vm.toString(i))));
            buyers.push(makeAddr(string.concat("buyer", vm.toString(i))));
        }
    }

    // ------------------------------------------------------------------ views for the suite

    function epochCount() external view returns (uint256) {
        return epochIds.length;
    }

    function policyCount() external view returns (uint256) {
        return policyIds.length;
    }

    function lpCount() external view returns (uint256) {
        return lps.length;
    }

    function ghostEpoch(uint256 id) external view returns (GhostEpoch memory) {
        return _ghostEpochs[id];
    }

    function ghostPolicy(uint256 id) external view returns (GhostPolicy memory) {
        return _ghostPolicies[id];
    }

    function refsHash(uint256 epochId) public view returns (bytes32) {
        ProtectionPool.EpochState memory s = pool.getEpochState(epochId);
        return keccak256(
            abi.encode(
                s.closePrice,
                s.openPrice,
                s.closeTime,
                s.openTime,
                s.gapBps,
                s.coveredBps,
                s.closeEvidence,
                s.openEvidence
            )
        );
    }

    // ------------------------------------------------------------------ helpers

    function _unexpected(string memory reason) internal {
        ++ghostUnexpected;
        lastUnexpected = reason;
    }

    function _success(bytes4 selector) internal {
        ++successes[selector];
        if (pool.paused()) ++pausedSuccesses;
    }

    function _activeEpoch() internal view returns (uint256 id, bool active) {
        if (epochIds.length == 0) return (0, false);
        id = epochIds[epochIds.length - 1];
        ProtectionPool.EpochStatus st = _ghostEpochs[id].status;
        active = st == ProtectionPool.EpochStatus.Open || st == ProtectionPool.EpochStatus.CloseRecorded;
    }

    function _lpLocked() internal view returns (bool) {
        (uint256 id, bool active) = _activeEpoch();
        return active && block.timestamp >= pool.getEpochConfig(id).saleCutoff;
    }

    function _bucketsSnapshot() internal view returns (bytes32) {
        return keccak256(abi.encode(ghostReserved, ghostPending, ghostClaimable, ghostFees));
    }

    function _checkBucketsMatchPool(string memory where) internal {
        if (
            pool.totalAssets() != ghostLpAssets || pool.reservedLiability() != ghostReserved
                || pool.pendingPremium() != ghostPending || pool.claimablePayouts() != ghostClaimable
                || pool.protocolFeesAccrued() != ghostFees
        ) _unexpected(where);
    }

    /// @dev Posts (or reuses) a snapshot as the oracle owner; returns updateData.
    function _snapshotData(uint256 price, uint64 refTime) internal returns (bytes memory) {
        bytes32 id = oracle.snapshotId(feedId, refTime);
        if (oracle.getSnapshot(id).postedAt == 0) {
            vm.prank(admin);
            oracle.postSnapshot(feedId, price, refTime);
        }
        return abi.encode(id);
    }

    // ------------------------------------------------------------------ epoch lifecycle

    function createEpoch(uint256 cutoffSeed, uint256 gapSeed, uint256 deadlineSeed) external {
        ++calls[this.createEpoch.selector];
        _createEpoch(cutoffSeed, gapSeed, deadlineSeed);
    }

    function _createEpoch(uint256 cutoffSeed, uint256 gapSeed, uint256 deadlineSeed) internal {
        (, bool active) = _activeEpoch();
        uint64 nowTs = uint64(block.timestamp);
        ProtectionPool.EpochConfig memory c;
        c.assetId = assetId;
        c.oracle = address(oracle);
        c.saleCutoff = nowTs + uint64(bound(cutoffSeed, 30 minutes, 6 hours));
        c.closeWindowStart = c.saleCutoff;
        c.closeWindowEnd = c.closeWindowStart + 30 minutes;
        c.openWindowStart = c.closeWindowEnd + uint64(bound(gapSeed, 1 hours, 12 hours));
        c.openWindowEnd = c.openWindowStart + 30 minutes;
        c.settlementDeadline = c.openWindowEnd + uint64(bound(deadlineSeed, 1 hours, 12 hours));
        c.triggerBps = 500;
        c.maxCoverBps = 500;
        c.premiumBps = 80;
        c.protocolFeeBps = 1200;
        c.minNotional = 10 * USDG;
        c.maxNotional = 10_000 * USDG;
        c.maxAggregateLiability = 100_000 * USDG;

        bool shouldSucceed = !active && !pool.paused();
        vm.prank(admin);
        try pool.createEpoch(c) returns (uint256 id) {
            if (!shouldSucceed) _unexpected("createEpoch succeeded while blocked");
            epochIds.push(id);
            _ghostEpochs[id].status = ProtectionPool.EpochStatus.Open;
        } catch {
            if (shouldSucceed) _unexpected("valid createEpoch reverted");
        }
    }

    function settleClose(uint256 refSeed, uint256 priceSeed) external {
        ++calls[this.settleClose.selector];
        if (pool.paused()) ++pausedLifecycleCalls;
        (uint256 id,) = _activeEpoch();
        if (id == 0) return;
        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(id);
        // Usually act like an operator and wait for the window; sometimes act early (invalid attempts).
        if (block.timestamp < c.closeWindowStart && refSeed % 4 != 0) {
            vm.warp(c.closeWindowStart + bound(priceSeed, 0, 20 minutes));
        }
        uint256 lo = c.closeWindowStart - 10 minutes;
        uint256 hi = Math.min(c.closeWindowEnd + 10 minutes, block.timestamp);
        if (hi < lo) return;
        uint64 refTime = uint64(bound(refSeed, lo, hi));
        bytes memory data = _snapshotData(bound(priceSeed, 5_000_000, 15_000_000), refTime);

        bool shouldSucceed = _ghostEpochs[id].status == ProtectionPool.EpochStatus.Open
            && block.timestamp < c.settlementDeadline && refTime >= c.closeWindowStart && refTime < c.closeWindowEnd;
        vm.prank(operator);
        try pool.settleClose(id, data) {
            if (!shouldSucceed) _unexpected("settleClose succeeded when invalid");
            _ghostEpochs[id].status = ProtectionPool.EpochStatus.CloseRecorded;
            _success(this.settleClose.selector);
        } catch {
            if (shouldSucceed) _unexpected("valid settleClose reverted");
        }
    }

    function settleOpen(uint256 refSeed, uint256 moveSeed) external {
        ++calls[this.settleOpen.selector];
        if (pool.paused()) ++pausedLifecycleCalls;
        (uint256 id,) = _activeEpoch();
        if (id == 0) return;
        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(id);
        if (block.timestamp < c.openWindowStart && refSeed % 4 != 0) {
            vm.warp(c.openWindowStart + bound(moveSeed, 0, 20 minutes));
        }
        uint256 lo = c.openWindowStart - 10 minutes;
        uint256 hi = Math.min(c.openWindowEnd + 10 minutes, block.timestamp);
        if (hi < lo) return;
        uint64 refTime = uint64(bound(refSeed, lo, hi));
        GhostEpoch storage g = _ghostEpochs[id];
        bool shouldSucceed = g.status == ProtectionPool.EpochStatus.CloseRecorded
            && block.timestamp < c.settlementDeadline && refTime >= c.openWindowStart && refTime < c.openWindowEnd;

        uint256 closePrice = shouldSucceed ? pool.getEpochState(id).closePrice : 10_000_000;
        // Open between -30% and +2% of close: covers calm, trigger boundary, partial and capped payouts.
        uint256 openPrice = closePrice * bound(moveSeed, 7000, 10_200) / BPS;
        if (openPrice == 0) openPrice = 1;
        bytes memory data = _snapshotData(openPrice, refTime);
        // A reused snapshot may carry a different price; settle on what the oracle actually stores.
        openPrice = oracle.getSnapshot(oracle.snapshotId(feedId, refTime)).price;

        vm.prank(operator);
        try pool.settleOpen(id, data) {
            if (!shouldSucceed) {
                _unexpected("settleOpen succeeded when invalid");
                return;
            }
            uint256 gap = closePrice > openPrice ? (closePrice - openPrice) * BPS / closePrice : 0;
            uint256 covered = gap <= c.triggerBps ? 0 : Math.min(gap - c.triggerBps, c.maxCoverBps);
            uint256 owed = g.soldNotional * covered / BPS;
            uint256 fee = g.premiumCollected * c.protocolFeeBps / BPS;
            ghostReserved -= g.soldLiability;
            ghostLpAssets = ghostLpAssets - owed + g.premiumCollected - fee;
            ghostClaimable += owed;
            ghostPending -= g.premiumCollected;
            ghostFees += fee;
            g.coveredBps = uint16(covered);
            g.status = ProtectionPool.EpochStatus.Settled;
            g.refsHash = refsHash(id);
            _success(this.settleOpen.selector);
            _checkBucketsMatchPool("settlement accounting mismatch");
        } catch {
            if (shouldSucceed) _unexpected("valid settleOpen reverted");
        }
    }

    function voidEpoch(uint256 epochSeed, uint256 callerSeed) external {
        ++calls[this.voidEpoch.selector];
        if (pool.paused()) ++pausedLifecycleCalls;
        if (epochIds.length == 0) return;
        uint256 id = epochIds[epochSeed % epochIds.length];
        GhostEpoch storage g = _ghostEpochs[id];
        // Sometimes simulate an oracle outage: let the deadline pass (or land exactly on it).
        uint64 deadline = pool.getEpochConfig(id).settlementDeadline;
        if (block.timestamp < deadline && callerSeed % 3 == 0) {
            vm.warp(callerSeed % 2 == 0 ? deadline : deadline + bound(epochSeed, 1, 2 hours));
        }
        bool active =
            g.status == ProtectionPool.EpochStatus.Open || g.status == ProtectionPool.EpochStatus.CloseRecorded;
        bool shouldSucceed = active && block.timestamp >= pool.getEpochConfig(id).settlementDeadline;
        address caller = address(uint160(bound(callerSeed, 1, type(uint160).max)));
        vm.prank(caller);
        try pool.voidEpoch(id) {
            if (!shouldSucceed) {
                _unexpected("voidEpoch succeeded when invalid");
                return;
            }
            ghostReserved -= g.soldLiability;
            g.status = ProtectionPool.EpochStatus.Voided;
            _success(this.voidEpoch.selector);
            _checkBucketsMatchPool("void accounting mismatch");
        } catch {
            if (shouldSucceed) _unexpected("valid voidEpoch reverted");
        }
    }

    function trySettleAsNonOperator(uint256 callerSeed) external {
        ++calls[this.trySettleAsNonOperator.selector];
        (uint256 id,) = _activeEpoch();
        if (id == 0) return;
        address caller = address(uint160(bound(callerSeed, 1, type(uint160).max)));
        if (caller == operator) return;
        vm.prank(caller);
        try pool.settleClose(id, abi.encode(bytes32(0))) {
            _unexpected("non-operator settled");
        } catch {}
        vm.prank(caller);
        try pool.settleOpen(id, abi.encode(bytes32(0))) {
            _unexpected("non-operator settled");
        } catch {}
    }

    // ------------------------------------------------------------------ LP flows

    function deposit(uint256 actorSeed, uint256 amount) external {
        ++calls[this.deposit.selector];
        _depositFor(lps[actorSeed % lps.length], bound(amount, 1, 1_000_000) * USDG);
    }

    function _depositFor(address lp, uint256 amount) internal {
        usdg.mint(lp, amount);
        bool shouldSucceed = !pool.paused() && !_lpLocked();
        vm.startPrank(lp);
        usdg.approve(address(pool), amount);
        try pool.deposit(amount, lp) {
            if (!shouldSucceed) _unexpected("deposit succeeded while closed");
            ghostLpAssets += amount;
        } catch {
            if (shouldSucceed) _unexpected("deposit reverted while open");
        }
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        ++calls[this.withdraw.selector];
        if (pool.paused()) ++pausedLifecycleCalls;
        address lp = lps[actorSeed % lps.length];
        uint256 maxW = pool.maxWithdraw(lp);
        uint256 free = _lpLocked() ? 0 : ghostLpAssets - ghostReserved;
        if (maxW > free) _unexpected("maxWithdraw exceeds model free collateral");
        amount = bound(amount, 0, maxW);
        bytes32 before = _bucketsSnapshot();
        vm.prank(lp);
        try pool.withdraw(amount, lp, lp) {
            ghostLpAssets -= amount;
        } catch {
            _unexpected("withdraw <= maxWithdraw reverted");
        }
        if (_bucketsSnapshot() != before) _unexpected("withdraw touched a non-LP bucket");
        _checkBucketsMatchPool("withdraw accounting mismatch");
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        ++calls[this.redeem.selector];
        if (pool.paused()) ++pausedLifecycleCalls;
        address lp = lps[actorSeed % lps.length];
        shares = bound(shares, 0, pool.maxRedeem(lp));
        vm.prank(lp);
        try pool.redeem(shares, lp, lp) returns (uint256 assets) {
            ghostLpAssets -= assets;
        } catch {
            _unexpected("redeem <= maxRedeem reverted");
        }
        _checkBucketsMatchPool("redeem accounting mismatch");
    }

    function withdrawTooMuch(uint256 actorSeed, uint256 excess) external {
        ++calls[this.withdrawTooMuch.selector];
        address lp = lps[actorSeed % lps.length];
        uint256 amount = pool.maxWithdraw(lp) + bound(excess, 1, 1_000_000 * USDG);
        vm.prank(lp);
        try pool.withdraw(amount, lp, lp) {
            _unexpected("withdrawal above maxWithdraw succeeded");
        } catch {}
    }

    // ------------------------------------------------------------------ buyers

    function buy(uint256 actorSeed, uint256 units) external {
        ++calls[this.buy.selector];
        // Orchestration: keep a market open and capitalised so purchases (and later claims) are common.
        (, bool anyActive) = _activeEpoch();
        if (!anyActive && !pool.paused()) _createEpoch(actorSeed, units, actorSeed ^ units);
        if (ghostLpAssets < 50_000 * USDG && !pool.paused() && !_lpLocked()) _depositFor(lps[0], 100_000 * USDG);
        (uint256 id, bool active) = _activeEpoch();
        if (id == 0) return;
        address buyer = buyers[actorSeed % buyers.length];
        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(id);
        uint256 notional = bound(units, c.minNotional / USDG, c.maxNotional / USDG) * USDG;
        uint256 premium = Math.mulDiv(notional, c.premiumBps, BPS, Math.Rounding.Ceil);
        uint256 maxPayout = notional * c.maxCoverBps / BPS;
        GhostEpoch storage g = _ghostEpochs[id];

        // Capacity uses the model's LP-owned assets only: claimable payouts, escrow and fees never count.
        bool shouldSucceed = active && g.status == ProtectionPool.EpochStatus.Open && !pool.paused()
            && block.timestamp < c.saleCutoff
            && ghostReserved + maxPayout <= ghostLpAssets * pool.utilizationCapBps() / BPS
            && g.soldLiability + maxPayout <= c.maxAggregateLiability;

        usdg.mint(buyer, premium);
        vm.startPrank(buyer);
        usdg.approve(address(pool), premium);
        try pool.buyProtection(id, notional) returns (uint256 policyId) {
            if (!shouldSucceed) _unexpected("purchase succeeded beyond limits");
            policyIds.push(policyId);
            _success(this.buy.selector);
            _ghostPolicies[policyId] = GhostPolicy({
                epochId: id,
                owner: buyer,
                notional: notional,
                premium: premium,
                maxPayout: maxPayout,
                claimed: false,
                claimCount: 0
            });
            g.soldNotional += notional;
            g.soldLiability += maxPayout;
            g.premiumCollected += premium;
            ghostReserved += maxPayout;
            ghostPending += premium;
        } catch {
            if (shouldSucceed) _unexpected("valid purchase reverted");
        }
        vm.stopPrank();
    }

    function claim(uint256 policySeed, uint256 callerSeed) external {
        ++calls[this.claim.selector];
        if (pool.paused()) ++pausedLifecycleCalls;
        if (policyIds.length == 0) return;
        uint256 policyId = policyIds[policySeed % policyIds.length];
        GhostPolicy storage p = _ghostPolicies[policyId];
        GhostEpoch storage g = _ghostEpochs[p.epochId];
        // 3 in 4 attempts come from the owner; the rest from another actor.
        address caller = callerSeed % 4 == 0 ? buyers[(callerSeed / 4) % buyers.length] : p.owner;
        bool settled = g.status == ProtectionPool.EpochStatus.Settled;
        bool finalized = settled || g.status == ProtectionPool.EpochStatus.Voided;
        bool shouldSucceed = caller == p.owner && !p.claimed && finalized;
        uint256 expected = settled ? p.notional * g.coveredBps / BPS : p.premium;

        uint256 balanceBefore = usdg.balanceOf(caller);
        vm.prank(caller);
        try pool.claim(policyId) returns (uint256 amount) {
            if (!shouldSucceed) {
                _unexpected("claim succeeded when invalid");
                return;
            }
            if (amount != expected || usdg.balanceOf(caller) - balanceBefore != amount) {
                _unexpected("claim paid the wrong amount");
            }
            if (settled && amount > p.maxPayout) _unexpected("claim exceeded max payout");
            p.claimed = true;
            ++p.claimCount;
            if (settled) ghostClaimable -= amount;
            else ghostPending -= amount;
            if (settled && amount > 0) {
                ++positiveClaims;
            }
            _success(this.claim.selector);
            _checkBucketsMatchPool("claim accounting mismatch");
        } catch {
            if (shouldSucceed) _unexpected("valid claim reverted");
        }
    }

    // ------------------------------------------------------------------ admin, time, misc

    function withdrawFees(uint256 amount) external {
        ++calls[this.withdrawFees.selector];
        amount = bound(amount, 0, ghostFees + 10);
        bool shouldSucceed = amount <= ghostFees;
        vm.prank(admin);
        try pool.withdrawProtocolFees(address(0xFEE), amount) {
            if (!shouldSucceed) _unexpected("fee withdrawal above accrued succeeded");
            ghostFees -= amount;
        } catch {
            if (shouldSucceed) _unexpected("valid fee withdrawal reverted");
        }
        _checkBucketsMatchPool("fee withdrawal accounting mismatch");
    }

    function warp(uint256 secondsForward) external {
        ++calls[this.warp.selector];
        vm.warp(block.timestamp + bound(secondsForward, 0, 3 hours));
    }

    function togglePause() external {
        ++calls[this.togglePause.selector];
        bool isPaused = pool.paused(); // read before prank: a view call would consume it
        vm.prank(admin);
        if (isPaused) pool.unpause();
        else pool.pause();
    }

    function donate(uint256 amount) external {
        ++calls[this.donate.selector];
        amount = bound(amount, 1, 100_000) * USDG;
        usdg.mint(address(pool), amount);
        ghostDonations += amount;
    }

    function tryTransferReceipt(uint256 policySeed, uint256 toSeed) external {
        ++calls[this.tryTransferReceipt.selector];
        if (policyIds.length == 0) return;
        uint256 policyId = policyIds[policySeed % policyIds.length];
        address from = receipt.ownerOf(policyId);
        address to = buyers[toSeed % buyers.length];
        if (to == from) to = lps[0];
        vm.prank(from);
        try receipt.transferFrom(from, to, policyId) {
            ++ghostReceiptTransferSuccesses;
        } catch {}
        vm.prank(from);
        try receipt.approve(to, policyId) {
            ++ghostReceiptTransferSuccesses;
        } catch {}
    }
}
