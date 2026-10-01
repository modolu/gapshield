// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ProtectionPool} from "../contracts/ProtectionPool.sol";
import {SnapshotOracle} from "../contracts/oracles/SnapshotOracle.sol";
import {MockUSDG} from "../contracts/mocks/MockUSDG.sol";

/// @notice Deploys GapShield: ProtectionPool (+ its ProtectionReceipt) and the TESTNET DEMO ORACLE (SnapshotOracle),
/// registers TSLA and sets the settlement operator.
///
/// Chains:
/// - 46630 Robinhood Chain Testnet: uses the official Paxos USDG (re-verify against docs.paxos.com before use).
/// - 31337 local Anvil / in-memory: deploys MockUSDG (LOCAL TEST ONLY).
///
/// The broadcaster becomes the owner of the pool and of the demo oracle. No private keys are read here; sign with
/// a Foundry keystore: `--account <name> --sender <address>`. Optional env: SETTLEMENT_OPERATOR (defaults to the
/// broadcaster). On a real broadcast the addresses are written to deployments/<chainId>.json.
contract DeployGapShield is Script {
    uint256 public constant ROBINHOOD_TESTNET = 46_630;
    uint256 public constant LOCAL = 31_337;
    /// @dev docs.paxos.com/guides/stablecoin/usdg/testnet, verified on-chain 2026-10-01 (docs/PHASE0_DECISIONS.md §3).
    address public constant ROBINHOOD_TESTNET_USDG = 0x7E955252E15c84f5768B83c41a71F9eba181802F;

    bytes32 public constant TSLA = keccak256("TSLA");
    /// @dev Pyth Pro `Equity.US.TSLA/USD`, pyth_lazer_id 1435, exponent -5 (docs/PHASE0_DECISIONS.md §6).
    bytes32 public constant TSLA_FEED_ID = bytes32(uint256(1435));
    uint8 public constant TSLA_PRICE_DECIMALS = 5;
    uint16 public constant UTILIZATION_CAP_BPS = 5000;

    error UnsupportedChain(uint256 chainId);
    error UnexpectedUsdg(string reason);

    struct Deployment {
        address usdg;
        address pool;
        address receipt;
        address oracle;
        address owner;
        address settlementOperator;
    }

    function run() external returns (Deployment memory d) {
        if (block.chainid == ROBINHOOD_TESTNET) {
            d.usdg = ROBINHOOD_TESTNET_USDG;
            _checkUsdg(d.usdg);
        } else if (block.chainid != LOCAL) {
            revert UnsupportedChain(block.chainid);
        }

        vm.startBroadcast();
        // The broadcasting account (keystore `--account`/`--sender`) owns everything it deploys.
        (, d.owner,) = vm.readCallers();
        d.settlementOperator = vm.envOr("SETTLEMENT_OPERATOR", d.owner);
        if (d.usdg == address(0)) d.usdg = address(new MockUSDG());
        SnapshotOracle oracle = new SnapshotOracle(d.owner);
        ProtectionPool pool = new ProtectionPool(IERC20Metadata(d.usdg), d.owner, UTILIZATION_CAP_BPS);
        pool.addAsset(TSLA, TSLA_FEED_ID, "TSLA", TSLA_PRICE_DECIMALS);
        pool.setSettlementOperator(d.settlementOperator);
        vm.stopBroadcast();

        d.pool = address(pool);
        d.receipt = address(pool.receipt());
        d.oracle = address(oracle);

        console2.log("chainId            ", block.chainid);
        console2.log("USDG               ", d.usdg);
        console2.log("ProtectionPool     ", d.pool);
        console2.log("ProtectionReceipt  ", d.receipt);
        console2.log("SnapshotOracle     ", d.oracle, "(TESTNET DEMO ORACLE)");
        console2.log("owner              ", d.owner);
        console2.log("settlementOperator ", d.settlementOperator);

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) _writeDeployment(d);
    }

    function _checkUsdg(address usdg) internal view {
        if (usdg.code.length == 0) revert UnexpectedUsdg("no code at USDG address");
        if (IERC20Metadata(usdg).decimals() != 6) revert UnexpectedUsdg("decimals != 6");
        if (keccak256(bytes(IERC20Metadata(usdg).symbol())) != keccak256("USDG")) revert UnexpectedUsdg("symbol");
    }

    function _writeDeployment(Deployment memory d) internal {
        string memory k = "deployment";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeUint(k, "blockNumber", block.number);
        vm.serializeAddress(k, "usdg", d.usdg);
        vm.serializeAddress(k, "protectionPool", d.pool);
        vm.serializeAddress(k, "protectionReceipt", d.receipt);
        vm.serializeAddress(k, "snapshotOracle", d.oracle);
        vm.serializeString(k, "snapshotOracleKind", "TESTNET DEMO ORACLE");
        vm.serializeAddress(k, "owner", d.owner);
        vm.serializeAddress(k, "settlementOperator", d.settlementOperator);
        vm.serializeBytes32(k, "tslaAssetId", TSLA);
        string memory json = vm.serializeBytes32(k, "tslaFeedId", TSLA_FEED_ID);
        vm.writeJson(json, string.concat("deployments/", vm.toString(block.chainid), ".json"));
    }
}
