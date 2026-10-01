// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title ProtectionReceipt
/// @notice Unique, non-transferable ERC-721 receipt per GapShield policy (`tokenId == policyId`).
/// Ownership identifies the claimant. The receipt holds no pricing or settlement logic.
/// @dev Only the pool can mint. Every transfer and burn reverts, as do approvals.
/// Implements the ERC-5192 `locked` view so wallets can show the token as non-transferable.
contract ProtectionReceipt is ERC721 {
    /// @dev ERC-5192 interface id.
    bytes4 private constant _ERC5192_INTERFACE_ID = 0xb45a3c0e;

    address public immutable pool;

    /// @notice ERC-5192: emitted once at mint; receipts are locked forever.
    event Locked(uint256 tokenId);

    error NotPool();
    error ZeroPool();
    error NonTransferable();

    constructor(address pool_) ERC721("GapShield Protection Receipt", "GSHIELD") {
        if (pool_ == address(0)) revert ZeroPool();
        pool = pool_;
    }

    function mint(address to, uint256 policyId) external {
        if (msg.sender != pool) revert NotPool();
        // `_mint`, not `_safeMint`: no receiver callback during purchase, and a non-transferable
        // receipt cannot become stuck — any owner (EOA or contract) can still claim through the pool.
        _mint(to, policyId);
        emit Locked(policyId);
    }

    /// @notice ERC-5192: every existing receipt is locked.
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    function approve(address, uint256) public pure override {
        revert NonTransferable();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert NonTransferable();
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == _ERC5192_INTERFACE_ID || super.supportsInterface(interfaceId);
    }

    /// @dev Only mints (from == address(0)) are allowed; transfers and burns revert.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert NonTransferable();
        return super._update(to, tokenId, auth);
    }
}
