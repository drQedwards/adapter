// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title WrappedENS
/// @notice Cross-chain ERC-721 mirror of ENS (.eth) names for use on chains other than
/// Ethereum mainnet (e.g. Base, Sepolia).
///
/// On Ethereum mainnet, ENS second-level .eth names are already ERC-721 tokens held by the
/// BaseRegistrar (0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85). On mainnet you can register
/// directly with the adapter — no wrapper needed:
///
///   adapter.register(
///       TokenStandard.ERC721,
///       0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85,  // ENS BaseRegistrar
///       uint256(keccak256("alice")),                    // ENS tokenId for "alice.eth"
///       agentURI
///   );
///
/// On other EVM chains (Base, Optimism, etc.) ENS names have no native representation.
/// Deploy this contract and point a trusted relayer at it. The relayer watches Ethereum
/// mainnet for BaseRegistrar transfers and calls `syncOwnership` here, letting an ERC-8004
/// agent on any EVM chain follow the ENS name owner live.
///
/// tokenId encoding
/// ----------------
/// tokenId = uint256(keccak256(abi.encodePacked(label)))
/// where label is the lowercased second-level label WITHOUT the .eth suffix, e.g. "alice"
/// for the name "alice.eth". This matches the ENS BaseRegistrar's own tokenId convention,
/// making it straightforward to cross-reference with on-chain ENS data on mainnet.
///
/// Registration example (Base, Optimism, etc.)
/// --------------------------------------------
/// After the relayer has called syncOwnership("alice", aliceEVMAddr):
///
///   adapter.register(
///       TokenStandard.ERC721,
///       address(wrappedENS),
///       wrappedENS.labelToTokenId("alice"),
///       agentURI
///   );
///
/// ENS NameWrapper (ERC-1155) note
/// --------------------------------
/// If the name is wrapped via the ENS NameWrapper, the owner on mainnet is the NameWrapper
/// contract and the per-name owner lives inside it. The relayer must resolve the wrapped
/// owner and supply it to `syncOwnership`. Cross-chain, this contract always represents
/// ownership as an ERC-721 regardless of whether the source is wrapped.
contract WrappedENS is ERC721, Ownable {
    /// @notice Address authorised to sync Ethereum mainnet ENS ownership to this contract.
    address public relayer;

    mapping(uint256 tokenId => string label) private _labels;

    error OnlyRelayer();
    error EVMTransfersBlocked();
    error LabelNotMinted(string label);

    event RelayerUpdated(address indexed previousRelayer, address indexed newRelayer);
    event OwnershipSynced(uint256 indexed tokenId, string label, address indexed newOwner);
    event LabelBurned(uint256 indexed tokenId, string label);

    modifier onlyRelayer() {
        if (msg.sender != relayer) revert OnlyRelayer();
        _;
    }

    constructor(address initialOwner, address initialRelayer) ERC721("Wrapped ENS", "wENS") Ownable(initialOwner) {
        relayer = initialRelayer;
        emit RelayerUpdated(address(0), initialRelayer);
    }

    // -------------------------------------------------------------------------
    // Relayer interface
    // -------------------------------------------------------------------------

    /// @notice Sync the EVM owner of an ENS .eth label from Ethereum mainnet.
    /// Mints if the label has not been bridged yet; updates owner otherwise.
    /// @param label Lowercased second-level label WITHOUT the .eth suffix, e.g. "alice".
    /// @param evmOwner EVM address that currently owns the name on Ethereum mainnet.
    function syncOwnership(string calldata label, address evmOwner) external onlyRelayer {
        uint256 tokenId = labelToTokenId(label);
        address current = _ownerOf(tokenId);
        if (current == address(0)) {
            _mint(evmOwner, tokenId);
            _labels[tokenId] = label;
        } else if (current != evmOwner) {
            _transfer(current, evmOwner, tokenId);
        }
        emit OwnershipSynced(tokenId, label, evmOwner);
    }

    /// @notice Burn the wrapped token when the ENS name expires on mainnet.
    function burn(string calldata label) external onlyRelayer {
        uint256 tokenId = labelToTokenId(label);
        if (_ownerOf(tokenId) == address(0)) revert LabelNotMinted(label);
        emit LabelBurned(tokenId, label);
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

    /// @notice Derive the tokenId for an ENS label. Matches the ENS BaseRegistrar convention.
    /// @param label Lowercased second-level label WITHOUT .eth, e.g. "alice".
    function labelToTokenId(string calldata label) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(label)));
    }

    /// @notice Returns the label stored for `tokenId`, or empty string if not minted.
    function labelOf(uint256 tokenId) external view returns (string memory) {
        return _labels[tokenId];
    }

    // -------------------------------------------------------------------------
    // Block EVM-side transfers — Ethereum mainnet is authoritative
    // -------------------------------------------------------------------------

    /// @dev auth is address(0) for internal _mint, _burn, _transfer (relayer path).
    /// auth is non-zero for public transferFrom / safeTransferFrom, which we reject.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (auth != address(0)) revert EVMTransfersBlocked();
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert EVMTransfersBlocked();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert EVMTransfersBlocked();
    }
}
