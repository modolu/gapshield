// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolTestBase} from "../utils/PoolTestBase.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";

contract ProtectionPoolAdminTest is PoolTestBase {
    function test_ownershipTransferIsTwoStep() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        pool.transferOwnership(newOwner);
        assertEq(pool.owner(), owner, "ownership unchanged until accepted");
        vm.prank(newOwner);
        pool.acceptOwnership();
        assertEq(pool.owner(), newOwner);
    }

    function test_renounceOwnershipDisabled() public {
        vm.prank(owner);
        vm.expectRevert(ProtectionPool.OwnershipCannotBeRenounced.selector);
        pool.renounceOwnership();
        assertEq(pool.owner(), owner);
    }

    function test_setSettlementOperator() public {
        vm.expectEmit(address(pool));
        emit ProtectionPool.SettlementOperatorSet(address(0), operator);
        vm.prank(owner);
        pool.setSettlementOperator(operator);
        assertEq(pool.settlementOperator(), operator);
    }

    function test_setSettlementOperator_onlyOwnerAndNonZero() public {
        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer1));
        pool.setSettlementOperator(buyer1);
        vm.prank(owner);
        vm.expectRevert(ProtectionPool.ZeroAddress.selector);
        pool.setSettlementOperator(address(0));
    }

    function test_assetAdminIsOwnerOnly() public {
        vm.startPrank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer1));
        pool.addAsset(keccak256("AAPL"), bytes32(uint256(922)), "AAPL", 5);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer1));
        pool.setAssetEnabled(TSLA, false);
        vm.stopPrank();
    }
}
