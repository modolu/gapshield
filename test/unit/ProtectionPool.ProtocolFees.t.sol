// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolProtocolFeesTest is PoolTestBase {
    uint256 internal constant P100 = 10_000_000;
    address internal treasury = makeAddr("treasury");
    uint256 internal epochId;
    uint256 internal p1;

    function setUp() public override {
        super.setUp();
        epochId = _createDefaultEpoch();
        _deposit(lp1, 10_000 * USDG);
        p1 = _buy(buyer1, epochId, 5000 * USDG); // premium 40, reserve 250
        _settle(epochId, P100, 9_200_000); // 8% gap -> 3% covered -> 150 owed
        // Leave escrow and reserve live in a second epoch so withdrawals are tested against every bucket.
        uint256 id2 = _createEpoch(_shiftedConfig(7 days));
        _buy(buyer2, id2, 1000 * USDG); // premium 8, reserve 50
    }

    function test_correctAccruedAmount() public view {
        assertEq(pool.protocolFeesAccrued(), 4_800_000); // 12% of 40 USDG
    }

    function test_onlyOwnerCanWithdraw() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        pool.withdrawProtocolFees(treasury, 1);
    }

    function test_cannotWithdrawMoreThanAccrued() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InsufficientProtocolFees.selector, 4_800_001, 4_800_000));
        pool.withdrawProtocolFees(treasury, 4_800_001);
    }

    function test_cannotWithdrawToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ProtectionPool.ZeroAddress.selector);
        pool.withdrawProtocolFees(address(0), 1);
    }

    function test_withdrawalTouchesOnlyFees() public {
        uint256 lpAssets = pool.totalAssets();
        uint256 reserved = pool.reservedLiability();
        uint256 pending = pool.pendingPremium();
        uint256 claimable = pool.claimablePayouts();
        assertEq(reserved, 50 * USDG);
        assertEq(pending, 8 * USDG);
        assertEq(claimable, 150 * USDG);

        vm.expectEmit(address(pool));
        emit ProtectionPool.ProtocolFeesWithdrawn(treasury, 4_800_000);
        vm.prank(owner);
        pool.withdrawProtocolFees(treasury, 4_800_000);

        assertEq(usdg.balanceOf(treasury), 4_800_000);
        assertEq(pool.protocolFeesAccrued(), 0);
        assertEq(pool.totalAssets(), lpAssets, "LP assets untouched");
        assertEq(pool.reservedLiability(), reserved, "reserve untouched");
        assertEq(pool.pendingPremium(), pending, "escrow untouched");
        assertEq(pool.claimablePayouts(), claimable, "claimable payouts untouched");
        assertEq(
            usdg.balanceOf(address(pool)),
            pool.totalAssets() + pool.pendingPremium() + pool.claimablePayouts() + pool.protocolFeesAccrued()
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InsufficientProtocolFees.selector, 1, 0));
        pool.withdrawProtocolFees(treasury, 1);
    }

    function test_partialWithdrawalAndWorksWhilePaused() public {
        vm.startPrank(owner);
        pool.pause();
        pool.withdrawProtocolFees(treasury, 1_000_000);
        vm.stopPrank();
        assertEq(pool.protocolFeesAccrued(), 3_800_000);
    }
}
