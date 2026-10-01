// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @title IReferenceOracle
/// @notice Stateless adapter that validates vendor-specific reference evidence for the ProtectionPool.
/// @dev Frozen in Phase 0 (docs/PHASE0_DECISIONS.md §9, P4). The pool is the settlement state-machine
/// authority: it calls this adapter, re-checks the returned window and price, and records each reference once.
/// Adapters never write pool state. Current implementation: SnapshotOracle (TESTNET DEMO ORACLE).
interface IReferenceOracle {
    /// @notice Verifies `updateData` as a reference for `feedId` inside `[windowStart, windowEnd)`.
    /// @dev Must revert on any failed check, including a market session other than the epoch's required session
    /// where the vendor exposes session metadata. Adapters that charge no fee must reject `msg.value > 0`.
    /// @return price Positive price in the asset's fixed exponent.
    /// @return referenceTime Unix seconds of the reference's own update time (Pyth: feedUpdateTimestamp / 1e6).
    /// @return evidence Hash binding the accepted vendor evidence.
    function verifyReference(bytes32 feedId, uint64 windowStart, uint64 windowEnd, bytes calldata updateData)
        external
        payable
        returns (uint256 price, uint64 referenceTime, bytes32 evidence);
}
