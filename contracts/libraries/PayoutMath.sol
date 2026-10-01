// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PayoutMath
/// @notice Downside-gap payout arithmetic. Every division rounds down.
library PayoutMath {
    uint256 internal constant BPS = 10_000;

    error ZeroClosePrice();

    /// @notice Worst-case payout reserved at purchase: `floor(notional * maxCoverBps / 10_000)`.
    function maxPayout(uint256 notional, uint256 maxCoverBps) internal pure returns (uint256) {
        return Math.mulDiv(notional, maxCoverBps, BPS);
    }

    /// @notice Downside gap in bps: `floor((closePrice - openPrice) * 10_000 / closePrice)`, or 0 if the open is not lower.
    /// @dev Result is at most 10_000.
    function gapBps(uint256 closePrice, uint256 openPrice) internal pure returns (uint256) {
        if (closePrice == 0) revert ZeroClosePrice();
        if (openPrice >= closePrice) return 0;
        return Math.mulDiv(closePrice - openPrice, BPS, closePrice);
    }

    /// @notice `min(max(gap - trigger, 0), maxCover)`.
    function coveredBps(uint256 gap, uint256 triggerBps, uint256 maxCoverBps) internal pure returns (uint256) {
        if (gap <= triggerBps) return 0;
        return Math.min(gap - triggerBps, maxCoverBps);
    }

    /// @notice `floor(notional * coveredBps / 10_000)`.
    function payout(uint256 notional, uint256 covered) internal pure returns (uint256) {
        return Math.mulDiv(notional, covered, BPS);
    }

    /// @notice Payout for a notional given close/open references and the tier terms.
    function payoutFor(uint256 notional, uint256 closePrice, uint256 openPrice, uint256 triggerBps, uint256 maxCoverBps)
        internal
        pure
        returns (uint256)
    {
        return payout(notional, coveredBps(gapBps(closePrice, openPrice), triggerBps, maxCoverBps));
    }
}
