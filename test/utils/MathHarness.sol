// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {PremiumMath} from "../../contracts/libraries/PremiumMath.sol";
import {PayoutMath} from "../../contracts/libraries/PayoutMath.sol";

/// @notice TEST ONLY. External wrappers so library reverts can be asserted with `vm.expectRevert`.
contract MathHarness {
    function premium(uint256 notional, uint256 premiumBps) external pure returns (uint256) {
        return PremiumMath.premium(notional, premiumBps);
    }

    function protocolFee(uint256 premiumAmount, uint256 feeBps) external pure returns (uint256) {
        return PremiumMath.protocolFee(premiumAmount, feeBps);
    }

    function maxPayout(uint256 notional, uint256 maxCoverBps) external pure returns (uint256) {
        return PayoutMath.maxPayout(notional, maxCoverBps);
    }

    function gapBps(uint256 closePrice, uint256 openPrice) external pure returns (uint256) {
        return PayoutMath.gapBps(closePrice, openPrice);
    }

    function coveredBps(uint256 gap, uint256 triggerBps, uint256 maxCoverBps) external pure returns (uint256) {
        return PayoutMath.coveredBps(gap, triggerBps, maxCoverBps);
    }

    function payout(uint256 notional, uint256 covered) external pure returns (uint256) {
        return PayoutMath.payout(notional, covered);
    }

    function payoutFor(uint256 notional, uint256 closePrice, uint256 openPrice, uint256 triggerBps, uint256 maxCover)
        external
        pure
        returns (uint256)
    {
        return PayoutMath.payoutFor(notional, closePrice, openPrice, triggerBps, maxCover);
    }
}
