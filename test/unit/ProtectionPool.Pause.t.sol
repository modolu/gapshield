// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolPauseTest is PoolTestBase {
    function _pause() internal {
        vm.prank(owner);
        pool.pause();
    }

    function test_pause_blocksDeposit() public {
        _pause();
        usdg.mint(lp1, 100 * USDG);
        vm.startPrank(lp1);
        usdg.approve(address(pool), 100 * USDG);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pool.deposit(100 * USDG, lp1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pool.mint(100 * USDG * 1e6, lp1);
        vm.stopPrank();
        assertEq(pool.maxDeposit(lp1), 0, "ERC-4626: maxDeposit is 0 while paused");
        assertEq(pool.maxMint(lp1), 0);
    }

    function test_pause_blocksPurchase() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 1000 * USDG);
        _pause();
        _fundBuyer(buyer1, 10 * USDG);
        vm.prank(buyer1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pool.buyProtection(epochId, 100 * USDG);
    }

    function test_pause_blocksNewEpoch() public {
        _pause();
        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pool.createEpoch(_defaultConfig());
    }

    function test_pause_blocksNewRiskConfiguration() public {
        _pause();
        vm.startPrank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pool.addAsset(keccak256("AAPL"), bytes32(uint256(922)), "AAPL", 5);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pool.setAssetEnabled(TSLA, false);
        vm.stopPrank();
    }

    function test_pause_genuinelyFreeWithdrawalRemainsAvailable() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 1000 * USDG);
        _buy(buyer1, epochId, 4000 * USDG); // reserve 200, free 800
        _pause();

        assertEq(pool.maxWithdraw(lp1), 800 * USDG);
        vm.prank(lp1);
        pool.withdraw(300 * USDG, lp1, lp1);
        uint256 shares = pool.maxRedeem(lp1);
        vm.prank(lp1);
        pool.redeem(shares, lp1, lp1);

        assertEq(pool.freeCollateral(), 0);
        assertEq(pool.reservedLiability(), 200 * USDG, "reserved claim capital never leaves");
        assertEq(usdg.balanceOf(lp1), 800 * USDG);
    }

    function test_pause_doesNotBlockOperatorRotation() public {
        _pause();
        vm.prank(owner);
        pool.setSettlementOperator(operator);
        assertEq(pool.settlementOperator(), operator);
    }

    function test_unpause_restoresDepositsAndPurchases() public {
        uint256 epochId = _createDefaultEpoch();
        _pause();
        vm.prank(owner);
        pool.unpause();
        _deposit(lp1, 1000 * USDG);
        _buy(buyer1, epochId, 100 * USDG);
    }

    function test_onlyOwnerCanPauseAndUnpause() public {
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer1));
        pool.pause();
        _pause();
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer1));
        pool.unpause();
    }
}
