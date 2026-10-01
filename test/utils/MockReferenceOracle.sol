// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IReferenceOracle} from "../../contracts/interfaces/IReferenceOracle.sol";

/// @notice TEST ONLY. Returns whatever it is told to, so tests can prove the pool's own re-checks
/// (positive price, reference time inside the window and not in the future) hold even against a faulty adapter.
contract MockReferenceOracle is IReferenceOracle {
    uint256 public price;
    uint64 public referenceTime;
    bytes32 public evidence;
    uint256 public lastValue;

    function set(uint256 price_, uint64 referenceTime_, bytes32 evidence_) external {
        price = price_;
        referenceTime = referenceTime_;
        evidence = evidence_;
    }

    function verifyReference(bytes32, uint64, uint64, bytes calldata)
        external
        payable
        returns (uint256, uint64, bytes32)
    {
        lastValue = msg.value;
        return (price, referenceTime, evidence);
    }
}
