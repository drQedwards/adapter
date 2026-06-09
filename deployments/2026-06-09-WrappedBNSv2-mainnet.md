# WrappedBNSv2 — Ethereum mainnet deployment

Date: 2026-06-09
Chain: Ethereum mainnet (chain id 1)

Deployed the `.btc` (BNS v2 / SIP-009) name bridge on Ethereum mainnet. Owner is
the project multisig **from birth** (passed as the constructor `initialOwner`),
so no separate `transferOwnership` step was needed — the deployer EOA never held
`owner()`. The relayer is unchanged from the other chains.

WrappedENS is intentionally **not** deployed on mainnet: `.eth` second-level names
are already ERC-721 tokens on the ENS BaseRegistrar
(`0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85`), so agents bind to it directly with
no wrapper.

## Address

| Field | Value |
|---|---|
| Contract | `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4` |
| Owner (multisig) | `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2` |
| Relayer (`syncOwnership` / `burn`) | `0xd83113dCf145bF72F640DbD2141dCB9B14A53789` |
| name / symbol | `Wrapped BNS v2` / `wBTCNAME` |

The contract address matches the Base deployment (`0xa98741B7…0563Dfa4`) because the
deployer EOA had the same nonce on both chains at deploy time (CREATE address =
`keccak256(rlp(deployer, nonce))`).

## Transaction

| Action | Tx hash | Gas used |
|---|---|---|
| Deploy (`CREATE`, owner = multisig) | `0x15e9ec0e0f62ffdd702fd348b9f240a61abb4a43a20b55c824edf871a96e4db7` | 1,382,223 |

Deployed at gas price ~0.39 gwei; cost ≈ 0.000474 ETH.

## Post-deploy verification

```
owner()   = 0x09CbC0D92AABE6F53Ac7E84F0Ba0FbfD05eB80f2
relayer() = 0xd83113dCf145bF72F640DbD2141dCB9B14A53789
name()    = "Wrapped BNS v2"
symbol()  = "wBTCNAME"
```
