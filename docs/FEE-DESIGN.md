# Fee design — monetizing the name bridges in good faith

Status: **proposed, not deployed.** This document plus `src/fees/MirrorFeeVault.sol`
are a reference implementation for review. Nothing here is live on any chain.

## Goal

Route a small fee to the project multisig (`0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2`)
for use of the cross-chain name-bridge infrastructure, **without** taxing ENS itself
and without weakening the unruggable guarantees the bridges already provide.

## What is *not* possible cleanly (and why)

- **A per-resolution / per-"ping" fee on ENS usage.** ens.domains/ens.app call the
  canonical ENS contracts on Ethereum mainnet. They never call our contracts, so there
  is no on-chain hook to charge. There is nothing to meter.
- **A fee inside `Adapter8004`.** Every write gates on `_requireBindingControl` /
  `_requireController` against `msg.sender`. To charge at `register`/`setAgentURI` you
  would have to modify the adapter. But the adapter is immutable per-implementation,
  UUPS-owned by a *different* Safe (`0x03302Df4…`), and shared by **all** bindings — not
  just bridge names. Taxing it would tax unrelated ERC-721/1155/6909 agents and works
  against the "good faith to the ENS DAO" posture. **Off the table.**

## What *is* clean: a fee on the service we actually provide

The bridges provide one thing of value that we control: **cross-chain mirroring** of a
name's ownership onto an EVM chain (so an ERC-8004 agent can follow it). That mirroring
is performed by our relayer. Charging a one-time fee to *request a mirror* monetizes our
own infrastructure, touches neither ENS nor the core adapter, and is naturally opt-in.

### Recommended: `MirrorFeeVault` (implemented)

A thin, standalone, payable contract:

1. A user calls `requestMirror{value: fee}(name, evmOwner)`.
2. The fee is forwarded immediately to the multisig (the vault never holds a balance).
3. A `MirrorRequested` event is emitted.
4. The relayer watches that event, **independently verifies** that the requester really
   controls `name` on the canonical chain (Stacks for `.btc`, Ethereum mainnet for `.eth`),
   and only then calls `bridge.syncOwnership(name, evmOwner)`.

Paying the fee grants **no** ownership — it only requests the off-chain service. The
relayer remains the sole authority that decides what gets mirrored, exactly as today.

Unruggable / good-faith guardrails baked in:

- **Immutable `maxFee` cap** set at deploy — the owner can never raise the fee above it.
- **Multisig-owned**; only the multisig can change the fee (within the cap) or recipient.
- **No custody**: funds are forwarded in the same call, so the vault can't be drained or
  frozen with user money inside.
- **Fee can be set to 0** to disable charging entirely.
- Charges only the mirroring service; never ENS resolution or name ownership.

### Alternative (documented, not implemented): `RegistrationFeeRouter`

Charge at agent-registration instead of at mirror time. Because `adapter.register`
requires the caller to control the bound token, the only no-adapter-change path is:

1. The name owner registers a delegate.xyz v2 delegation to the router contract.
2. The owner calls `router.registerWithFee{value: fee}(...)`, which forwards the fee to
   the multisig and then calls `adapter.register(...)`. The adapter sees the router as a
   valid delegate of the token owner, so the control check passes; the resulting agent is
   still controlled by the live name owner.

Trade-offs vs. the vault: requires an extra delegate.xyz setup tx, is easy to bypass
(the owner can just call `adapter.register` directly for free), and couples the fee to
the adapter's delegation semantics. Use only if a per-agent (rather than per-name) charge
is required.

## Recommendation

Ship `MirrorFeeVault` with `mirrorFee = 0` initially (so behavior is unchanged) and a
conservative `maxFee` cap. Turn on a small fee later via the multisig if desired. This
keeps the system free and good-faith by default while making monetization a one-multisig-tx
switch — with a hard ceiling the multisig itself cannot exceed.
