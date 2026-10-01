// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract SevenDecimalToken is ERC20 {
    constructor() ERC20("Wrong", "WRONG") {}

    function decimals() public pure override returns (uint8) {
        return 7;
    }
}

contract ProtectionPoolVaultTest is PoolTestBase {
    function test_constructor_rejectsNonSixDecimalAsset() public {
        SevenDecimalToken wrong = new SevenDecimalToken();
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.UnsupportedAssetDecimals.selector, 7));
        new ProtectionPool(IERC20Metadata(address(wrong)), owner, UTILIZATION_CAP_BPS);
    }

    function test_constructor_rejectsInvalidUtilizationCap() public {
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidUtilizationCap.selector, 0));
        new ProtectionPool(usdg, owner, 0);
        vm.expectRevert(abi.encodeWithSelector(ProtectionPool.InvalidUtilizationCap.selector, 10_001));
        new ProtectionPool(usdg, owner, 10_001);
    }

    function test_constructor_wiresReceiptAndAsset() public view {
        assertEq(pool.asset(), address(usdg));
        assertEq(receipt.pool(), address(pool));
        assertEq(pool.utilizationCapBps(), 5000);
        assertEq(pool.decimals(), 12, "6 USDG decimals + 6 virtual-share offset");
    }

    function test_deposit() public {
        uint256 shares = _deposit(lp1, 1000 * USDG);
        assertEq(shares, 1000 * USDG * 1e6);
        assertEq(pool.balanceOf(lp1), shares);
        assertEq(pool.totalAssets(), 1000 * USDG);
        assertEq(pool.freeCollateral(), 1000 * USDG);
        assertEq(usdg.balanceOf(address(pool)), 1000 * USDG);
    }

    function test_deposit_emitsEvents() public {
        usdg.mint(lp1, 100 * USDG);
        vm.startPrank(lp1);
        usdg.approve(address(pool), 100 * USDG);
        vm.expectEmit(address(pool));
        emit ProtectionPool.LiquidityDeposited(lp1, lp1, 100 * USDG, 100 * USDG * 1e6);
        vm.expectEmit(address(pool));
        emit IERC4626.Deposit(lp1, lp1, 100 * USDG, 100 * USDG * 1e6);
        pool.deposit(100 * USDG, lp1);
        vm.stopPrank();
    }

    function test_shareAccounting_twoLps() public {
        _deposit(lp1, 3000 * USDG);
        _deposit(lp2, 1000 * USDG);
        assertEq(pool.balanceOf(lp1), 3 * pool.balanceOf(lp2));
        assertEq(pool.convertToAssets(pool.balanceOf(lp1)), 3000 * USDG);
        assertEq(pool.convertToAssets(pool.balanceOf(lp2)), 1000 * USDG);

        uint256 lp2Shares = pool.balanceOf(lp2);
        vm.prank(lp2);
        uint256 assets = pool.redeem(lp2Shares, lp2, lp2);
        assertEq(assets, 1000 * USDG);
        assertEq(usdg.balanceOf(lp2), 1000 * USDG);
        assertEq(pool.totalAssets(), 3000 * USDG);
    }

    function test_mint_pathTracksLpAssets() public {
        usdg.mint(lp1, 500 * USDG);
        vm.startPrank(lp1);
        usdg.approve(address(pool), 500 * USDG);
        uint256 assets = pool.mint(500 * USDG * 1e6, lp1);
        vm.stopPrank();
        assertEq(assets, 500 * USDG);
        assertEq(pool.totalAssets(), 500 * USDG);
    }

    function test_donationDoesNotChangeLpAccounting() public {
        _deposit(lp1, 1000 * USDG);
        usdg.mint(address(pool), 777 * USDG); // direct transfer, not a deposit
        assertEq(pool.totalAssets(), 1000 * USDG);
        assertEq(pool.freeCollateral(), 1000 * USDG);
        assertEq(pool.convertToAssets(pool.balanceOf(lp1)), 1000 * USDG);
    }

    function test_freeCollateralCalculation() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 2000 * USDG);
        _buy(buyer1, epochId, 4000 * USDG); // reserve 200
        assertEq(pool.reservedLiability(), 200 * USDG);
        assertEq(pool.freeCollateral(), 1800 * USDG);
        assertEq(pool.freeCollateral(), pool.totalAssets() - pool.reservedLiability());
    }

    function test_lpCannotWithdrawReservedClaimCapital() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 1000 * USDG);
        _buy(buyer1, epochId, 10_000 * USDG); // reserve 500 (utilization cap)

        assertEq(pool.maxWithdraw(lp1), 500 * USDG);
        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, lp1, 500 * USDG + 1, 500 * USDG)
        );
        pool.withdraw(500 * USDG + 1, lp1, lp1);

        uint256 maxShares = pool.maxRedeem(lp1);
        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, lp1, maxShares + 1, maxShares)
        );
        pool.redeem(maxShares + 1, lp1, lp1);

        vm.prank(lp1);
        pool.withdraw(500 * USDG, lp1, lp1);
        assertEq(pool.totalAssets(), 500 * USDG);
        assertEq(pool.reservedLiability(), 500 * USDG);
        assertEq(pool.freeCollateral(), 0);
        assertEq(pool.maxWithdraw(lp1), 0);
        assertEq(pool.pendingPremium(), 80 * USDG, "escrowed premium untouched by LP withdrawal");
        assertEq(usdg.balanceOf(address(pool)), 580 * USDG);
    }

    function test_maxRedeemNeverExceedsFreeCollateral() public {
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 1000 * USDG);
        _deposit(lp2, 333 * USDG);
        _buy(buyer1, epochId, 7777 * USDG);
        uint256 shares = pool.maxRedeem(lp1);
        assertLe(pool.previewRedeem(shares), pool.freeCollateral());
        vm.prank(lp1);
        pool.redeem(shares, lp1, lp1);
        assertLe(pool.reservedLiability(), pool.totalAssets());
    }

    function test_depositsAndWithdrawalsLockFromCutoff() public {
        _createDefaultEpoch();
        _deposit(lp1, 1000 * USDG);
        vm.warp(SALE_CUTOFF);

        assertEq(pool.maxDeposit(lp1), 0);
        assertEq(pool.maxMint(lp1), 0);
        assertEq(pool.maxWithdraw(lp1), 0, "even free collateral is locked until settled/voided");
        assertEq(pool.maxRedeem(lp1), 0);

        usdg.mint(lp2, 10 * USDG);
        vm.startPrank(lp2);
        usdg.approve(address(pool), 10 * USDG);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, lp2, 10 * USDG, 0));
        pool.deposit(10 * USDG, lp2);
        vm.stopPrank();

        vm.prank(lp1);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, lp1, 1, 0));
        pool.withdraw(1, lp1, lp1);
    }

    /// @notice Regression (Phase 1 bug #1, found by invariant_handlerOutcomesMatchModel): after cutoff the
    /// max* views return 0, but `_withdraw` rejected even zero-amount withdrawals/redemptions, contradicting
    /// ERC-4626 (an amount within max* must not revert) and the pool's own views.
    function test_regression_zeroWithdrawAndRedeemAfterCutoffDoNotRevert() public {
        _createDefaultEpoch();
        _deposit(lp1, 1000 * USDG);
        vm.warp(SALE_CUTOFF);
        assertEq(pool.maxRedeem(lp1), 0);
        vm.startPrank(lp1);
        assertEq(pool.redeem(0, lp1, lp1), 0);
        assertEq(pool.withdraw(0, lp1, lp1), 0);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, lp1, 1, 0));
        pool.withdraw(1, lp1, lp1);
        vm.stopPrank();
        assertEq(pool.totalAssets(), 1000 * USDG);
    }

    function test_depositsOpenBeforeCutoffDuringActiveEpoch() public {
        _createDefaultEpoch();
        vm.warp(SALE_CUTOFF - 1);
        _deposit(lp1, 100 * USDG);
        assertEq(pool.totalAssets(), 100 * USDG);
    }

    function test_withdrawToOtherReceiverWithAllowance() public {
        _deposit(lp1, 100 * USDG);
        uint256 shares = pool.balanceOf(lp1);
        vm.prank(lp1);
        pool.approve(lp2, shares);
        vm.prank(lp2);
        pool.redeem(shares, lp2, lp1);
        assertEq(usdg.balanceOf(lp2), 100 * USDG);
        assertEq(pool.totalAssets(), 0);
    }
}
