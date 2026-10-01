// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ProtectionPool} from "../../contracts/ProtectionPool.sol";
import {ProtectionReceipt} from "../../contracts/ProtectionReceipt.sol";
import {MockUSDG} from "../../contracts/mocks/MockUSDG.sol";

/// @notice Drives the pool through bounded random LP, buyer, time, pause, donation and receipt actions.
/// Each action asserts its own expected outcome (success vs. revert) against an independent model, and
/// maintains ghost totals that the invariant suite compares with on-chain accounting.
contract PoolHandler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant USDG = 1e6;

    ProtectionPool public immutable pool;
    ProtectionReceipt public immutable receipt;
    MockUSDG public immutable usdg;
    address public immutable admin;
    uint256 public immutable epochId;

    address[] public lps;
    address[] public buyers;

    // Ghost accounting
    uint256 public ghostLpDeposited;
    uint256 public ghostLpWithdrawn;
    uint256 public ghostPremiums;
    uint256 public ghostDonations;
    uint256 public ghostReceiptTransferSuccesses;
    uint256 public ghostMaxWithdrawViolations;

    uint256[] public policyIds;
    mapping(uint256 policyId => address) public ghostOwner;
    mapping(uint256 policyId => uint256) public ghostNotional;
    mapping(uint256 policyId => uint256) public ghostPremium;
    mapping(uint256 policyId => uint256) public ghostMaxPayout;

    mapping(bytes4 selector => uint256) public calls;

    /// @dev Count of actions whose outcome contradicted the model; asserted to be zero by the suite.
    uint256 public ghostUnexpected;
    string public lastUnexpected;

    function _unexpected(string memory reason) internal {
        ++ghostUnexpected;
        lastUnexpected = reason;
    }

    constructor(ProtectionPool pool_, MockUSDG usdg_, address admin_, uint256 epochId_) {
        pool = pool_;
        receipt = pool_.receipt();
        usdg = usdg_;
        admin = admin_;
        epochId = epochId_;
        for (uint256 i; i < 3; ++i) {
            lps.push(makeAddr(string.concat("lp", vm.toString(i))));
            buyers.push(makeAddr(string.concat("buyer", vm.toString(i))));
        }
    }

    function policyCount() external view returns (uint256) {
        return policyIds.length;
    }

    function lpCount() external view returns (uint256) {
        return lps.length;
    }

    // ------------------------------------------------------------------ actions

    function deposit(uint256 actorSeed, uint256 amount) external {
        ++calls[this.deposit.selector];
        address lp = lps[actorSeed % lps.length];
        amount = bound(amount, 1, 1_000_000) * USDG;
        usdg.mint(lp, amount);
        vm.startPrank(lp);
        usdg.approve(address(pool), amount);
        bool shouldSucceed = pool.maxDeposit(lp) > 0;
        try pool.deposit(amount, lp) {
            if (!shouldSucceed) _unexpected("deposit succeeded while closed");
            ghostLpDeposited += amount;
        } catch {
            if (shouldSucceed) _unexpected("deposit reverted while open");
        }
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        ++calls[this.withdraw.selector];
        address lp = lps[actorSeed % lps.length];
        uint256 maxW = pool.maxWithdraw(lp);
        if (maxW > pool.freeCollateral()) ++ghostMaxWithdrawViolations;
        amount = bound(amount, 0, maxW);
        uint256 reservedBefore = pool.reservedLiability();
        vm.prank(lp);
        try pool.withdraw(amount, lp, lp) {
            ghostLpWithdrawn += amount;
        } catch {
            _unexpected("withdraw <= maxWithdraw reverted");
        }
        if (pool.reservedLiability() != reservedBefore) _unexpected("withdraw changed reserve");
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        ++calls[this.redeem.selector];
        address lp = lps[actorSeed % lps.length];
        shares = bound(shares, 0, pool.maxRedeem(lp));
        vm.prank(lp);
        try pool.redeem(shares, lp, lp) returns (uint256 assets) {
            ghostLpWithdrawn += assets;
        } catch {
            _unexpected("redeem <= maxRedeem reverted");
        }
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

    function buy(uint256 actorSeed, uint256 units) external {
        ++calls[this.buy.selector];
        address buyer = buyers[actorSeed % buyers.length];
        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(epochId);
        uint256 notional = bound(units, c.minNotional / USDG, c.maxNotional / USDG) * USDG;
        uint256 premium = Math.mulDiv(notional, c.premiumBps, 10_000, Math.Rounding.Ceil);
        uint256 maxPayout = notional * c.maxCoverBps / 10_000;

        bool shouldSucceed = !pool.paused() && block.timestamp < c.saleCutoff
            && pool.reservedLiability() + maxPayout <= pool.totalAssets() * pool.utilizationCapBps() / 10_000
            && pool.getEpochState(epochId).soldLiability + maxPayout <= c.maxAggregateLiability;

        usdg.mint(buyer, premium);
        vm.startPrank(buyer);
        usdg.approve(address(pool), premium);
        try pool.buyProtection(epochId, notional) returns (uint256 policyId) {
            if (!shouldSucceed) _unexpected("purchase succeeded beyond limits");
            policyIds.push(policyId);
            ghostOwner[policyId] = buyer;
            ghostNotional[policyId] = notional;
            ghostPremium[policyId] = premium;
            ghostMaxPayout[policyId] = maxPayout;
            ghostPremiums += premium;
        } catch {
            if (shouldSucceed) _unexpected("valid purchase reverted");
        }
        vm.stopPrank();
    }

    function warp(uint256 secondsForward) external {
        ++calls[this.warp.selector];
        vm.warp(block.timestamp + bound(secondsForward, 0, 2 hours));
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
