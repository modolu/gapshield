// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDG
/// @notice LOCAL TEST ONLY. 6-decimal stand-in for Paxos USDG with unrestricted minting.
/// Never deploy to a public network; testnet deployments use the official Paxos USDG address.
contract MockUSDG is ERC20 {
    constructor() ERC20("Mock Global Dollar (LOCAL TEST ONLY)", "mUSDG") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
