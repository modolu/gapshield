// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionReceipt} from "../../contracts/ProtectionReceipt.sol";

contract ProtectionReceiptTest is PoolTestBase {
    uint256 internal policyId;

    function setUp() public override {
        super.setUp();
        uint256 epochId = _createDefaultEpoch();
        _deposit(lp1, 1000 * USDG);
        policyId = _buy(buyer1, epochId, 1000 * USDG);
    }

    function test_correctOwnerReceivesReceipt() public view {
        assertEq(receipt.ownerOf(policyId), buyer1);
        assertEq(receipt.balanceOf(buyer1), 1);
        assertEq(receipt.name(), "GapShield Protection Receipt");
        assertEq(receipt.symbol(), "GSHIELD");
    }

    function test_transferFromReverts() public {
        vm.prank(buyer1);
        vm.expectRevert(ProtectionReceipt.NonTransferable.selector);
        receipt.transferFrom(buyer1, buyer2, policyId);
        assertEq(receipt.ownerOf(policyId), buyer1);
    }

    function test_safeTransferFromReverts() public {
        vm.startPrank(buyer1);
        vm.expectRevert(ProtectionReceipt.NonTransferable.selector);
        receipt.safeTransferFrom(buyer1, buyer2, policyId);
        vm.expectRevert(ProtectionReceipt.NonTransferable.selector);
        receipt.safeTransferFrom(buyer1, buyer2, policyId, "");
        vm.stopPrank();
        assertEq(receipt.ownerOf(policyId), buyer1);
    }

    function test_approvalsRevert() public {
        vm.startPrank(buyer1);
        vm.expectRevert(ProtectionReceipt.NonTransferable.selector);
        receipt.approve(buyer2, policyId);
        vm.expectRevert(ProtectionReceipt.NonTransferable.selector);
        receipt.setApprovalForAll(buyer2, true);
        vm.stopPrank();
        assertFalse(receipt.isApprovedForAll(buyer1, buyer2));
        assertEq(receipt.getApproved(policyId), address(0));
    }

    function test_unauthorizedMintRejected() public {
        vm.prank(buyer2);
        vm.expectRevert(ProtectionReceipt.NotPool.selector);
        receipt.mint(buyer2, 999);
    }

    function test_poolCannotRemintOrReassignExistingReceipt() public {
        // Even the pool cannot change ownership of an existing receipt.
        vm.prank(address(pool));
        vm.expectRevert(ProtectionReceipt.NonTransferable.selector);
        receipt.mint(buyer2, policyId);
        assertEq(receipt.ownerOf(policyId), buyer1);
    }

    function test_noBurnPath() public {
        // There is no burn function; a transfer to the zero address is also rejected.
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        receipt.transferFrom(buyer1, address(0), policyId);
        assertEq(receipt.ownerOf(policyId), buyer1);
    }

    function test_constructorRejectsZeroPool() public {
        vm.expectRevert(ProtectionReceipt.ZeroPool.selector);
        new ProtectionReceipt(address(0));
    }

    function test_erc5192Locked() public {
        assertTrue(receipt.locked(policyId));
        assertTrue(receipt.supportsInterface(0xb45a3c0e));
        assertTrue(receipt.supportsInterface(type(IERC721).interfaceId));
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 999));
        receipt.locked(999);
    }

    function test_mintEmitsLocked() public {
        uint256 epochId = pool.activeEpochId();
        _fundBuyer(buyer2, 1 * USDG);
        vm.expectEmit(address(receipt));
        emit ProtectionReceipt.Locked(2);
        vm.prank(buyer2);
        pool.buyProtection(epochId, 100 * USDG);
        assertEq(receipt.ownerOf(2), buyer2);
    }
}
