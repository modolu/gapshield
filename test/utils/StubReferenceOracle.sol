// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IReferenceOracle} from "../../contracts/interfaces/IReferenceOracle.sol";

/// @notice TEST ONLY. Gives epochs a contract address for their frozen `oracle` field.
/// Phase 1 never settles, so verification always reverts.
contract StubReferenceOracle is IReferenceOracle {
    error NotImplemented();

    function verifyReference(bytes32, uint64, uint64, bytes calldata)
        external
        payable
        returns (uint256, uint64, bytes32)
    {
        revert NotImplemented();
    }
}
