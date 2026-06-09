// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title WrappedBNSv2
/// @notice Cross-chain ERC-721 mirror of BNS v2 (.btc) SIP-009 NFTs on the Stacks blockchain.
///
/// A trusted relayer watches Stacks for ownership changes and calls `syncOwnership` to keep
/// this contract current. The Adapter8004 binds to this token via its standard ERC-721 path —
/// no adapter changes are required. Because `ownerOf` is evaluated live on every adapter call,
/// control of the bound ERC-8004 agent follows the .btc name automatically as it transfers on
/// Stacks.
///
/// Stacks is the authoritative owner ledger. EVM-side transfers are blocked; all ownership
/// changes flow through the relayer. The delegate.xyz v2 hot-wallet path on the adapter still
/// works: a cold wallet that holds the wrapped NFT can delegate a hot EVM wallet without the
/// relayer needing to do anything.
///
/// tokenId encoding
/// ----------------
/// tokenId = uint256(keccak256(abi.encodePacked(canonicalName)))
/// where canonicalName is the lowercased fully-qualified name, e.g. "alice.btc".
/// This is deterministic across all EVM chains so the same tokenId can be used wherever
/// this contract is deployed.
///
/// Registration example
/// --------------------
/// After the relayer has called syncOwnership("alice.btc", aliceEVMAddr):
///
///   adapter.register(
///       TokenStandard.ERC721,
///       address(wrappedBNSv2),
///       wrappedBNSv2.nameToTokenId("alice.btc"),
///       agentURI
///   );
contract WrappedBNSv2 is ERC721, Ownable {
    /// @notice Address authorised to sync Stacks ownership to this contract.
    address public relayer;

    mapping(uint256 tokenId => string bnsName) private _names;

    error OnlyRelayer();
    error EVMTransfersBlocked();
    error NameNotMinted(string name);

    event RelayerUpdated(address indexed previousRelayer, address indexed newRelayer);
    event OwnershipSynced(uint256 indexed tokenId, string name, address indexed newOwner);
    event NameBurned(uint256 indexed tokenId, string name);

    modifier onlyRelayer() {
        if (msg.sender != relayer) revert OnlyRelayer();
        _;
    }

    constructor(address initialOwner, address initialRelayer)
        ERC721("Wrapped BNS v2", "wBTCNAME")
        Ownable(initialOwner)
    {
        relayer = initialRelayer;
        emit RelayerUpdated(address(0), initialRelayer);
    }

    // -------------------------------------------------------------------------
    // Relayer interface
    // -------------------------------------------------------------------------

    /// @notice Sync the EVM owner of a BNS v2 name from Stacks.
    /// Mints if the name has not been bridged yet; updates owner otherwise.
    /// @param canonicalName Lowercased fully-qualified name, e.g. "alice.btc".
    /// @param evmOwner EVM address that currently controls the name on Stacks.
    function syncOwnership(string calldata canonicalName, address evmOwner) external onlyRelayer {
        uint256 tokenId = nameToTokenId(canonicalName);
        address current = _ownerOf(tokenId);
        if (current == address(0)) {
            _mint(evmOwner, tokenId);
            _names[tokenId] = canonicalName;
        } else if (current != evmOwner) {
            _transfer(current, evmOwner, tokenId);
        }
        emit OwnershipSynced(tokenId, canonicalName, evmOwner);
    }

    /// @notice Burn the wrapped token when the name expires or is released on Stacks.
    /// The name mapping is preserved so a later re-registration re-mints cleanly.
    function burn(string calldata canonicalName) external onlyRelayer {
        uint256 tokenId = nameToTokenId(canonicalName);
        if (_ownerOf(tokenId) == address(0)) revert NameNotMinted(canonicalName);
        emit NameBurned(tokenId, canonicalName);
        _burn(tokenId);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function setRelayer(address newRelayer) external onlyOwner {
        address prev = relayer;
        relayer = newRelayer;
        emit RelayerUpdated(prev, newRelayer);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Derive the deterministic tokenId for a BNS v2 name.
    /// @param canonicalName Lowercased fully-qualified name, e.g. "alice.btc".
    function nameToTokenId(string calldata canonicalName) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(canonicalName)));
    }

    /// @notice Returns the BNS name stored for `tokenId`.
    /// Returns an empty string for tokenIds that were never minted or have been burned.
    function nameOf(uint256 tokenId) external view returns (string memory) {
        return _names[tokenId];
    }

    // -------------------------------------------------------------------------
    // Block EVM-side transfers — Stacks is authoritative
    // -------------------------------------------------------------------------

    /// @dev In OZ v5, _update is the unified hook for mint / transfer / burn.
    /// auth is address(0) for internal _mint, _burn, and _transfer calls (used
    /// by the relayer). auth is non-zero for public transferFrom / safeTransferFrom,
    /// which we reject so that Stacks remains the sole authority.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (auth != address(0)) revert EVMTransfersBlocked();
        return super._update(to, tokenId, auth);
    }

    /// @dev Approvals are meaningless when EVM transfers are blocked.
    function approve(address, uint256) public pure override {
        revert EVMTransfersBlocked();
    }

    /// @dev Operator approvals are meaningless when EVM transfers are blocked.
    function setApprovalForAll(address, bool) public pure override {
        revert EVMTransfersBlocked();
    }
}
