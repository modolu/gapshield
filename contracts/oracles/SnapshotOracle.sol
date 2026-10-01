// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IReferenceOracle} from "../interfaces/IReferenceOracle.sol";

/// @title SnapshotOracle — TESTNET DEMO ORACLE
/// @notice TESTNET DEMO ORACLE. Prices are posted by a single trusted operator (the owner); nothing here is
/// verified against a market data source. It exists so the full GapShield lifecycle can be demonstrated on a
/// testnet and in local tests. It is NOT a production oracle and must never back real-money settlement.
/// @dev Implements the frozen `IReferenceOracle` (docs/PHASE0_DECISIONS.md §9, P4):
/// - the owner posts each snapshot on-chain first, with an event; snapshots are immutable once posted;
/// - `updateData` only references a stored snapshot (`abi.encode(bytes32 snapshotId)`); prices are never
///   supplied inline at settlement;
/// - verification is stateless: it checks the feed, the half-open window and positivity, and returns
///   normalized data. It holds no epoch state and never calls the pool.
/// Snapshots carry no market-session metadata, so no session check applies.
contract SnapshotOracle is IReferenceOracle, Ownable2Step {
    /// @notice On-chain label so explorers and the app can always show what backs an epoch.
    string public constant ORACLE_KIND = "TESTNET DEMO ORACLE";

    struct Snapshot {
        bytes32 feedId;
        uint256 price;
        uint64 referenceTime;
        uint64 postedAt;
    }

    mapping(bytes32 snapshotId => Snapshot) private _snapshots;

    event SnapshotPosted(
        bytes32 indexed snapshotId, bytes32 indexed feedId, uint256 price, uint64 referenceTime, address poster
    );

    error ZeroFeedId();
    error ZeroPrice();
    error FutureReferenceTime(uint64 referenceTime, uint256 blockTime);
    error SnapshotAlreadyPosted(bytes32 snapshotId);
    error UnknownSnapshot(bytes32 snapshotId);
    error FeedMismatch(bytes32 expected, bytes32 actual);
    error OutsideWindow(uint64 referenceTime, uint64 windowStart, uint64 windowEnd);
    error FeeNotAccepted();
    error MalformedUpdateData();
    error OwnershipCannotBeRenounced();

    constructor(address owner_) Ownable(owner_) {}

    /// @notice Deterministic id: one snapshot per feed per second.
    function snapshotId(bytes32 feedId, uint64 referenceTime) public pure returns (bytes32) {
        return keccak256(abi.encode(feedId, referenceTime));
    }

    /// @notice Posts an immutable snapshot. Only the owner (testnet operator) can post.
    function postSnapshot(bytes32 feedId, uint256 price, uint64 referenceTime) external onlyOwner returns (bytes32 id) {
        if (feedId == bytes32(0)) revert ZeroFeedId();
        if (price == 0) revert ZeroPrice();
        if (referenceTime > block.timestamp) revert FutureReferenceTime(referenceTime, block.timestamp);
        id = snapshotId(feedId, referenceTime);
        if (_snapshots[id].postedAt != 0) revert SnapshotAlreadyPosted(id);
        _snapshots[id] =
            Snapshot({feedId: feedId, price: price, referenceTime: referenceTime, postedAt: uint64(block.timestamp)});
        emit SnapshotPosted(id, feedId, price, referenceTime, msg.sender);
    }

    function getSnapshot(bytes32 id) external view returns (Snapshot memory) {
        return _snapshots[id];
    }

    /// @inheritdoc IReferenceOracle
    function verifyReference(bytes32 feedId, uint64 windowStart, uint64 windowEnd, bytes calldata updateData)
        external
        payable
        returns (uint256 price, uint64 referenceTime, bytes32 evidence)
    {
        if (msg.value != 0) revert FeeNotAccepted();
        if (updateData.length != 32) revert MalformedUpdateData();
        bytes32 id = abi.decode(updateData, (bytes32));

        Snapshot storage snap = _snapshots[id];
        if (snap.postedAt == 0) revert UnknownSnapshot(id);
        if (snap.feedId != feedId) revert FeedMismatch(feedId, snap.feedId);
        if (snap.referenceTime < windowStart || snap.referenceTime >= windowEnd) {
            revert OutsideWindow(snap.referenceTime, windowStart, windowEnd);
        }
        // Positivity is enforced when posting (snapshots are immutable) and re-checked by the pool.

        price = snap.price;
        referenceTime = snap.referenceTime;
        evidence = keccak256(abi.encode(block.chainid, address(this), id, snap.feedId, snap.price, snap.referenceTime));
    }

    /// @dev An ownerless demo oracle could never post again; renouncing is disabled.
    function renounceOwnership() public view override onlyOwner {
        revert OwnershipCannotBeRenounced();
    }
}
