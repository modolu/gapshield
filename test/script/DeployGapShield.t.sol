// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {DeployGapShield} from "../../script/DeployGapShield.s.sol";
import {CreateDemoEpoch} from "../../script/CreateDemoEpoch.s.sol";
import {ProtectionPool} from "../../contracts/ProtectionPool.sol";
import {SnapshotOracle} from "../../contracts/oracles/SnapshotOracle.sol";

contract DeployGapShieldTest is Test {
    function test_localDeploymentIsWiredCorrectly() public {
        DeployGapShield script = new DeployGapShield();
        DeployGapShield.Deployment memory d = script.run();
        ProtectionPool pool = ProtectionPool(d.pool);
        assertEq(pool.asset(), d.usdg);
        assertEq(address(pool.receipt()), d.receipt);
        assertEq(pool.utilizationCapBps(), 5000);
        assertEq(pool.settlementOperator(), d.settlementOperator);
        assertEq(pool.owner(), d.owner);
        assertEq(SnapshotOracle(d.oracle).owner(), d.owner);
        assertEq(SnapshotOracle(d.oracle).ORACLE_KIND(), "TESTNET DEMO ORACLE");
        ProtectionPool.Asset memory a = pool.getAsset(keccak256("TSLA"));
        assertEq(a.oracleFeedId, bytes32(uint256(1435)));
        assertEq(a.priceDecimals, 5);
        assertTrue(a.enabled);
    }

    function test_rejectsUnsupportedChain() public {
        DeployGapShield script = new DeployGapShield();
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(DeployGapShield.UnsupportedChain.selector, 1));
        script.run();
    }

    function test_demoEpochScriptOpensCompressedEpoch() public {
        DeployGapShield deploy = new DeployGapShield();
        DeployGapShield.Deployment memory d = deploy.run();
        vm.setEnv("POOL", vm.toString(d.pool));
        vm.setEnv("ORACLE", vm.toString(d.oracle));
        CreateDemoEpoch demo = new CreateDemoEpoch();
        // The deploy script's broadcaster (default sender) owns the pool and broadcasts here too.
        uint256 epochId = demo.run();
        ProtectionPool.EpochConfig memory c = ProtectionPool(d.pool).getEpochConfig(epochId);
        assertEq(c.saleCutoff, block.timestamp + 10 minutes);
        assertEq(c.settlementDeadline, c.openWindowEnd + 30 minutes);
        assertEq(c.oracle, d.oracle);
    }
}
