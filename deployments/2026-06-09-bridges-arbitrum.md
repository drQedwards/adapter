# Bridge deployment — Arbitrum One

Date: 2026-06-09
Chain: Arbitrum One (chain id 42161)

Deployed both name bridges on Arbitrum One. Owner is the project multisig **from
birth** (constructor `initialOwner`), so no `transferOwnership` was needed. Relayer
unchanged from the other chains.

Deploy funds were bridged from Ethereum mainnet to the relayer EOA via the canonical
Arbitrum Delayed Inbox `depositEth()` (L1 tx
`0x103c3b337dcb2ca82d421dcc3ead172490bef1a0f530f0b8b6d201721364afae`, 0.0002 ETH,
credited on L2 in ~9.5 min).

## Addresses

| Contract | Address | Owner (multisig) | Relayer |
|---|---|---|---|
| WrappedBNSv2 | `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4` | `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2` | `0xd83113dCf145bF72F640DbD2141dCB9B14A53789` |
| WrappedENS | `0xC7AFf3b228b8353d1811802F90f389815431a194` | `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2` | `0xd83113dCf145bF72F640DbD2141dCB9B14A53789` |

Both addresses match the Base (and, for WrappedBNSv2, mainnet) deployments — the
deployer EOA's nonce was aligned across chains, so CREATE produced identical addresses.

## Transactions

| Action | Tx hash |
|---|---|
| Deploy WrappedBNSv2 | `0x092e12df802f2f4d772d40c914983008b65ad52646e2d2ff2f2bfbf2c2538a2e` |
| Deploy WrappedENS | `0x636922afeef0a01cb13a8f7adff6a7ef09b2bf6fdb3ce284a68cbe9d06eb4716` |

Deployed at ~0.02 gwei; both deploys cost ≈ 0.000058 ETH combined.

## Adapter status on Arbitrum

The ERC-8004 IdentityRegistry (`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`) **is**
deployed on Arbitrum, but the Adapter8004 proxy is **not** yet. The bridges therefore
mirror names today; agent `register()` through the adapter becomes available once an
adapter proxy is deployed on Arbitrum.
