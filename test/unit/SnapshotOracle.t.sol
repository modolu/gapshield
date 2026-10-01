// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SnapshotOracle} from "../../contracts/oracles/SnapshotOracle.sol";

contract SnapshotOracleTest is Test {
    bytes32 internal constant FEED = bytes32(uint256(1435));
    address internal owner = makeAddr("owner");
    SnapshotOracle internal oracle;

    uint64 internal constant T = 1_790_971_140;

    function setUp() public {
        vm.warp(T + 1 hours);
        oracle = new SnapshotOracle(owner);
    }

    function _post(uint256 price, uint64 refTime) internal returns (bytes memory) {
        vm.prank(owner);
        return abi.encode(oracle.postSnapshot(FEED, price, refTime));
    }

    function test_labelledAsTestnetDemo() public view {
        assertEq(oracle.ORACLE_KIND(), "TESTNET DEMO ORACLE");
    }

    function test_postAndVerify_returnsNormalizedReference() public {
        bytes memory data = _post(10_000_000, T);
        bytes32 id = abi.decode(data, (bytes32));
        (uint256 price, uint64 refTime, bytes32 evidence) = oracle.verifyReference(FEED, T, T + 60, data);
        assertEq(price, 10_000_000);
        assertEq(refTime, T);
        assertEq(evidence, keccak256(abi.encode(block.chainid, address(oracle), id, FEED, uint256(10_000_000), T)));
        SnapshotOracle.Snapshot memory s = oracle.getSnapshot(id);
        assertEq(s.price, 10_000_000);
        assertEq(s.postedAt, block.timestamp);
    }

    function test_post_emitsEvent() public {
        bytes32 id = oracle.snapshotId(FEED, T);
        vm.expectEmit(address(oracle));
        emit SnapshotOracle.SnapshotPosted(id, FEED, 42, T, owner);
        _post(42, T);
    }

    function test_onlyOwnerCanPost() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        oracle.postSnapshot(FEED, 1, T);
    }

    function test_snapshotsAreImmutable() public {
        _post(10_000_000, T);
        bytes32 id = oracle.snapshotId(FEED, T); // computed before prank: a view call would consume it
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.SnapshotAlreadyPosted.selector, id));
        oracle.postSnapshot(FEED, 1, T);
    }

    function test_postRejectsZeroPriceZeroFeedAndFutureTime() public {
        vm.startPrank(owner);
        vm.expectRevert(SnapshotOracle.ZeroPrice.selector);
        oracle.postSnapshot(FEED, 0, T);
        vm.expectRevert(SnapshotOracle.ZeroFeedId.selector);
        oracle.postSnapshot(bytes32(0), 1, T);
        uint64 future = uint64(block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.FutureReferenceTime.selector, future, block.timestamp));
        oracle.postSnapshot(FEED, 1, future);
        vm.stopPrank();
    }

    function test_verify_rejectsWrongFeed() public {
        bytes memory data = _post(100, T);
        bytes32 other = bytes32(uint256(922));
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.FeedMismatch.selector, other, FEED));
        oracle.verifyReference(other, T, T + 60, data);
    }

    function test_verify_rejectsBeforeAndAtWindowEnd() public {
        bytes memory data = _post(100, T);
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.OutsideWindow.selector, T, T + 1, T + 60));
        oracle.verifyReference(FEED, T + 1, T + 60, data);
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.OutsideWindow.selector, T, T - 60, T));
        oracle.verifyReference(FEED, T - 60, T, data);
        // inclusive start, exclusive end
        oracle.verifyReference(FEED, T, T + 1, data);
    }

    function test_verify_rejectsUnknownSnapshotAndMalformedData() public {
        bytes32 missing = keccak256("missing");
        vm.expectRevert(abi.encodeWithSelector(SnapshotOracle.UnknownSnapshot.selector, missing));
        oracle.verifyReference(FEED, T, T + 60, abi.encode(missing));
        vm.expectRevert(SnapshotOracle.MalformedUpdateData.selector);
        oracle.verifyReference(FEED, T, T + 60, hex"1234");
    }

    function test_verify_rejectsFee() public {
        bytes memory data = _post(100, T);
        vm.deal(address(this), 1 ether);
        vm.expectRevert(SnapshotOracle.FeeNotAccepted.selector);
        oracle.verifyReference{value: 1}(FEED, T, T + 60, data);
    }

    function test_renounceOwnershipDisabled() public {
        vm.prank(owner);
        vm.expectRevert(SnapshotOracle.OwnershipCannotBeRenounced.selector);
        oracle.renounceOwnership();
    }
}
