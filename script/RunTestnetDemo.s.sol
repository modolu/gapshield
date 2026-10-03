// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ProtectionPool} from "../contracts/ProtectionPool.sol";
import {SnapshotOracle} from "../contracts/oracles/SnapshotOracle.sol";
import {CreateDemoEpoch} from "./CreateDemoEpoch.s.sol";

/// @notice TESTNET DEMO driver for a live end-to-end lifecycle on already-deployed contracts. Settlement uses the
/// SnapshotOracle (TESTNET DEMO ORACLE): the broadcaster posts the reference prices. Not production settlement.
///
/// Idempotent: every step reads chain state first and is skipped if it already happened, so re-running a phase
/// never repeats a transaction. The broadcaster must be the pool owner, settlement operator and oracle owner.
///
/// Env: POOL, ORACLE (required); DEMO_PHASE = "start" | "settle"; DEMO_NOTIONAL_USDG (default 1000);
/// DEMO_CLOSE_PRICE (default 10000000 = 100.00000); DEMO_OPEN_PRICE (default 9100000 = 91.00000);
/// DEMO_POLICY_ID (settle phase: policy to claim; 0 = skip). `start` also uses CreateDemoEpoch's DEMO_* timing.
///
/// - start:  void the previous epoch if it is past its settlement deadline, open a demo epoch (CreateDemoEpoch),
///           approve exactly the premium if the allowance is short, and buy protection.
/// - settle: post the close snapshot and settleClose (once the close window has started), then post the open
///           snapshot and settleOpen (once the open window has started), then claim DEMO_POLICY_ID.
contract RunTestnetDemo is Script {
    uint256 internal constant USDG = 1e6;
    /// @dev Reference times are taken this far into each window (and never in the future).
    uint64 internal constant REF_OFFSET = 60;

    ProtectionPool internal pool;
    SnapshotOracle internal oracle;

    error PreviousEpochStillActive(uint256 epochId, uint64 settlementDeadline, uint256 nowTs);
    error WindowNotReached(string which, uint64 notBefore, uint256 nowTs);
    error SnapshotPriceMismatch(bytes32 snapshotId, uint256 posted, uint256 wanted);

    function run() external {
        pool = ProtectionPool(vm.envAddress("POOL"));
        oracle = SnapshotOracle(vm.envAddress("ORACLE"));
        console2.log("oracle kind:", oracle.ORACLE_KIND());
        bytes32 phase = keccak256(bytes(vm.envString("DEMO_PHASE")));
        if (phase == keccak256("start")) _start();
        else if (phase == keccak256("settle")) _settle();
        else revert("DEMO_PHASE must be start or settle");
    }

    function _isActive(ProtectionPool.EpochStatus s) internal pure returns (bool) {
        return s == ProtectionPool.EpochStatus.Open || s == ProtectionPool.EpochStatus.CloseRecorded;
    }

    function _start() internal {
        uint256 prev = pool.activeEpochId();
        if (prev != 0 && _isActive(pool.getEpochState(prev).status)) {
            uint64 deadline = pool.getEpochConfig(prev).settlementDeadline;
            if (block.timestamp < deadline) revert PreviousEpochStillActive(prev, deadline, block.timestamp);
            console2.log("voidEpoch", prev);
            vm.broadcast();
            pool.voidEpoch(prev);
        }

        uint256 epochId = new CreateDemoEpoch().run();

        uint256 notional = vm.envOr("DEMO_NOTIONAL_USDG", uint256(1000)) * USDG;
        (uint256 premium, uint256 maxPayout) = pool.quote(epochId, notional);
        IERC20 usdg = IERC20(pool.asset());
        vm.startBroadcast();
        (, address buyer,) = vm.readCallers();
        if (usdg.allowance(buyer, address(pool)) < premium) {
            console2.log("approve premium", premium);
            usdg.approve(address(pool), premium);
        } else {
            console2.log("existing allowance covers premium", usdg.allowance(buyer, address(pool)));
        }
        uint256 policyId = pool.buyProtection(epochId, notional);
        vm.stopBroadcast();

        console2.log("epochId  ", epochId);
        console2.log("policyId ", policyId);
        console2.log("notional ", notional);
        console2.log("premium  ", premium);
        console2.log("maxPayout", maxPayout);
    }

    function _settle() internal {
        uint256 epochId = pool.activeEpochId();
        ProtectionPool.EpochConfig memory c = pool.getEpochConfig(epochId);
        bytes32 feedId = pool.getAsset(c.assetId).oracleFeedId;
        console2.log("epochId", epochId);

        if (pool.getEpochState(epochId).status == ProtectionPool.EpochStatus.Open) {
            uint64 ref = c.closeWindowStart + REF_OFFSET;
            if (block.timestamp < ref) revert WindowNotReached("close", ref, block.timestamp);
            bytes memory data = _snapshot(feedId, vm.envOr("DEMO_CLOSE_PRICE", uint256(10_000_000)), ref);
            console2.log("settleClose ref", ref);
            vm.broadcast();
            pool.settleClose(epochId, data);
        }

        if (pool.getEpochState(epochId).status == ProtectionPool.EpochStatus.CloseRecorded) {
            uint64 ref = c.openWindowStart + REF_OFFSET;
            if (block.timestamp < ref) {
                // Exit cleanly (no revert) so the close settlement above is still broadcast.
                console2.log("close recorded; re-run settle at or after open reference time", ref);
                return;
            }
            bytes memory data = _snapshot(feedId, vm.envOr("DEMO_OPEN_PRICE", uint256(9_100_000)), ref);
            console2.log("settleOpen ref", ref);
            vm.broadcast();
            pool.settleOpen(epochId, data);
        }

        uint256 policyId = vm.envOr("DEMO_POLICY_ID", uint256(0));
        if (policyId != 0 && !pool.getPolicy(policyId).claimed) {
            console2.log("claim policy", policyId, "payout", pool.previewPayout(policyId));
            vm.broadcast();
            pool.claim(policyId);
        }
    }

    /// @dev Posts the TESTNET DEMO snapshot unless it already exists with the same price; returns updateData.
    function _snapshot(bytes32 feedId, uint256 price, uint64 refTime) internal returns (bytes memory) {
        bytes32 id = oracle.snapshotId(feedId, refTime);
        uint256 posted = oracle.getSnapshot(id).price;
        if (posted == 0) {
            console2.log("postSnapshot", price, refTime);
            vm.broadcast();
            oracle.postSnapshot(feedId, price, refTime);
        } else if (posted != price) {
            revert SnapshotPriceMismatch(id, posted, price);
        } else {
            console2.log("snapshot already posted", refTime);
        }
        return abi.encode(id);
    }
}
