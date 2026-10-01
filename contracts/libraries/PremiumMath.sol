// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PremiumMath
/// @notice Fixed-premium arithmetic. Premium rounds up; the protocol fee rounds down.
library PremiumMath {
    uint256 internal constant BPS = 10_000;

    /// @notice `ceil(notional * premiumBps / 10_000)`.
    function premium(uint256 notional, uint256 premiumBps) internal pure returns (uint256) {
        return Math.mulDiv(notional, premiumBps, BPS, Math.Rounding.Ceil);
    }

    /// @notice `floor(premiumAmount * protocolFeeBps / 10_000)`.
    function protocolFee(uint256 premiumAmount, uint256 protocolFeeBps) internal pure returns (uint256) {
        return Math.mulDiv(premiumAmount, protocolFeeBps, BPS);
    }
}
