// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MirrorFeeVault
/// @notice Optional, opt-in service fee for the cross-chain name-mirroring the bridges provide.
///
/// A user pays a flat fee to *request* that a name be mirrored onto an EVM chain; the fee is
/// forwarded in the same call to the project multisig, and a `MirrorRequested` event is emitted.
/// The relayer watches that event and — only after independently verifying that the requester
/// actually controls the name on its canonical chain (Stacks for `.btc`, Ethereum mainnet for
/// `.eth`) — calls `syncOwnership` on the relevant bridge.
///
/// Paying the fee grants NO ownership and bypasses NO check. It is a request for an off-chain
/// service; the relayer remains the sole authority over what gets mirrored, exactly as before.
/// This contract touches neither the immutable bridges nor the core `Adapter8004`.
///
/// Unruggable guarantees:
/// - `maxFee` is immutable, fixed at deploy — the owner can never set a fee above it.
/// - The vault never holds a balance: every payment is forwarded to `feeRecipient` in-call.
/// - Only the owner (the multisig) can change the fee (within the cap) or the recipient.
/// - Setting `mirrorFee` to 0 disables charging entirely.
contract MirrorFeeVault is Ownable {
    /// @notice Hard ceiling on `mirrorFee`, fixed at construction and immutable thereafter.
    uint256 public immutable maxFee;

    /// @notice Flat fee (wei) required to request a mirror. Owner-settable in [0, maxFee].
    uint256 public mirrorFee;

    /// @notice Destination for collected fees (the project multisig).
    address public feeRecipient;

    error FeeTooHigh(uint256 requested, uint256 maxFee);
    error InsufficientFee(uint256 sent, uint256 required);
    error ZeroAddress();
    error FeeForwardFailed();

    event MirrorRequested(
        bytes32 indexed nameHash, string name, address indexed payer, address indexed evmOwner, uint256 feePaid
    );
    event MirrorFeeUpdated(uint256 previousFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    constructor(address initialOwner, address initialFeeRecipient, uint256 initialFee, uint256 maxFee_)
        Ownable(initialOwner)
    {
        if (initialFeeRecipient == address(0)) revert ZeroAddress();
        if (initialFee > maxFee_) revert FeeTooHigh(initialFee, maxFee_);
        feeRecipient = initialFeeRecipient;
        mirrorFee = initialFee;
        maxFee = maxFee_;
        emit FeeRecipientUpdated(address(0), initialFeeRecipient);
        emit MirrorFeeUpdated(0, initialFee);
    }

    /// @notice Pay the mirror fee and emit a request the relayer can act on.
    /// @dev The full `msg.value` (which must be >= `mirrorFee`) is forwarded to `feeRecipient`;
    /// any overpayment is treated as a tip. The relayer MUST independently verify canonical
    /// ownership of `name` before mirroring — this call confers no rights on its own.
    /// @param name The canonical name being requested (e.g. "alice.btc" or "alice" for alice.eth).
    /// @param evmOwner The EVM address that should receive the mirrored token once verified.
    function requestMirror(string calldata name, address evmOwner) external payable {
        uint256 fee = mirrorFee;
        if (msg.value < fee) revert InsufficientFee(msg.value, fee);
        (bool ok,) = feeRecipient.call{value: msg.value}("");
        if (!ok) revert FeeForwardFailed();
        emit MirrorRequested(keccak256(bytes(name)), name, msg.sender, evmOwner, msg.value);
    }

    /// @notice Update the flat mirror fee. Capped at the immutable `maxFee`.
    function setMirrorFee(uint256 newFee) external onlyOwner {
        if (newFee > maxFee) revert FeeTooHigh(newFee, maxFee);
        emit MirrorFeeUpdated(mirrorFee, newFee);
        mirrorFee = newFee;
    }

    /// @notice Update the fee destination.
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }
}
