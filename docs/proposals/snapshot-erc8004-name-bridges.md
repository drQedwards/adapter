# [Snapshot Proposal] Cross-chain ERC-8004 name bridges for ENS — deployed contracts & optional service fee

- **Platform:** snapshot.xyz
- **Author:** jkdrq.eth
- **Owner multisig:** `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2`
- **Status:** Ready for temperature check / vote
- **Type:** Social / Informational (ratify deployed infrastructure; authorize optional fee switch)

---

## Abstract

This proposal asks the community to acknowledge a set of **already-deployed, multisig-owned**
contracts that let an ENS `.eth` name (and a Stacks `.btc` name) control an
[ERC-8004](https://eips.ethereum.org/) agent identity across chains, and to give a
non-binding signal on enabling a small, capped service fee for the cross-chain mirroring
infrastructure.

The contracts are designed **in good faith to the ENS DAO**: they never wrap, gate, or tax
canonical ENS on Ethereum mainnet, they cannot move a name independently of its mainnet
owner, and they hold no custody of ENS names or of user funds.

## Motivation

ERC-8004 defines an on-chain agent identity registry. The Adapter8004 protocol re-routes
control of an ERC-8004 agent from `ownerOf(agentId)` to **whoever currently holds a bound
external token** — so a name a user already owns can drive an agent with no extra registry.

On Ethereum mainnet, `.eth` second-level names are already ERC-721 tokens on the ENS
BaseRegistrar and bind to the adapter **directly, with no wrapper**. On other chains (Base,
Arbitrum, …) ENS names have no native representation, so a thin mirror is required for an
agent on those chains to follow the canonical mainnet owner. These bridges provide exactly
that mirror — and nothing more.

## Specification — deployed contracts

All addresses are live and **owned from birth by the multisig** `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2`.
The relayer (`syncOwnership` / `burn` only) is `0xd83113dCf145bF72F640DbD2141dCB9B14A53789`.

### WrappedENS (`.eth` mirror, non-mainnet only)

| Chain | Address |
|---|---|
| Base | `0xC7AFf3b228b8353d1811802F90f389815431a194` |
| Arbitrum One | `0xC7AFf3b228b8353d1811802F90f389815431a194` |

> **Not deployed on Ethereum mainnet by design.** On mainnet, bind directly to the ENS
> BaseRegistrar `0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85`.

`tokenId = uint256(keccak256(abi.encodePacked(label)))` — identical to the ENS BaseRegistrar
convention, so a wrapped tokenId cross-references mainnet ENS data directly.

### WrappedBNSv2 (`.btc` / Stacks SIP-009 mirror)

| Chain | Address |
|---|---|
| Ethereum mainnet | `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4` |
| Base | `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4` |
| Arbitrum One | `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4` |

### Adapter8004 (the protocol these bridges feed)

| Chain | Proxy |
|---|---|
| Ethereum mainnet | `0xde152AfB7db5373F34876E1499fbD893A82dD336` |
| Base | `0x270d25D2c59A8bcA1B0f40ad95fF7806c0025c27` |
| Sepolia | `0x7621630cB63a73a194f45A3E6801B8C6A7eC2f92` |

ERC-8004 registry (mainnet, Base, Arbitrum): `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`.

## Trust model — why this is unruggable and ENS-respecting

Each property below was **verified live on-chain** during deployment testing
(Base agent `54943`; mirror txs on mainnet and Arbitrum):

1. **Mainnet is authoritative.** Every EVM-side move on a wrapped token — `transferFrom`,
   `safeTransferFrom`, `approve`, `setApprovalForAll` — reverts with `EVMTransfersBlocked`.
   A wrapped name on Base/Arbitrum can change hands **only** when the relayer mirrors a real
   transfer from the canonical chain. It can never diverge from mainnet ENS.
2. **No name custody.** The bridge mirrors *ownership*; it never holds, escrows, or can
   seize an ENS name. The canonical name stays on mainnet under its real owner.
3. **No identity extraction.** The ERC-8004 agent NFT is held permanently by the adapter.
   The name owner *drives* the agent through the adapter but can never pull the agent NFT out.
4. **Control follows the owner with zero transactions.** When a name moves on the canonical
   chain and the relayer syncs, agent control moves automatically — no adapter tx, no
   re-registration.
5. **Multisig governance, no unilateral relayer power.** Only the relayer can `syncOwnership`
   / `burn`; only the multisig can rotate the relayer. No third party can touch a name.
6. **ENS resolution is never touched or charged.** ens.domains / ens.app interact only with
   canonical ENS contracts; these bridges are invisible to them and add no cost to ENS usage.

## Optional service fee (the part this vote signals on)

A reference contract, **`MirrorFeeVault`** (`src/fees/MirrorFeeVault.sol`, 16 tests passing,
**not yet deployed**), would let the project charge a small, flat fee to *request* that a
name be mirrored to an EVM chain. The fee is forwarded in the same call to the multisig; the
relayer still independently verifies canonical ownership before mirroring. Paying grants no
rights and bypasses no check.

Guardrails (good-faith by construction):

- **Immutable `maxFee` ceiling** fixed at deploy — the owner can never exceed it.
- **Zero custody** — fees are forwarded in-call; the vault never holds a balance.
- **Multisig-only** fee/recipient changes.
- **Fee = 0 by default** (disabled); enabling it is a single multisig transaction.
- Charges the **mirroring service only** — never ENS resolution or name ownership.

This monetizes the cross-chain relayer infrastructure the project runs, not ENS itself.

## Recommendation

Ratify the deployed bridges as good-faith, ENS-respecting infrastructure, and authorize the
multisig to deploy `MirrorFeeVault` with `mirrorFee = 0` and a conservative `maxFee` cap, to
be enabled later (if ever) by a subsequent multisig action.

## Voting options

- **For** — Acknowledge the deployed bridges and authorize the capped, default-off fee vault.
- **Against** — Do not authorize the fee vault; keep mirroring free with no fee contract.
- **Abstain**

---

### Appendix — verification commands

```sh
# Owner / relayer on each bridge (any chain RPC)
cast call 0xC7AFf3b228b8353d1811802F90f389815431a194 'owner()(address)'   --rpc-url $RPC
cast call 0xC7AFf3b228b8353d1811802F90f389815431a194 'relayer()(address)' --rpc-url $RPC

# Transfers are blocked (expect revert 0xe406f414 = EVMTransfersBlocked)
cast call 0xa98741B7EE20B096a6262A705A088f8c0563Dfa4 \
  'transferFrom(address,address,uint256)' $FROM $TO $TOKENID --from $FROM --rpc-url $RPC
```
