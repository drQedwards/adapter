# Bridge ownership transfer — Base mainnet

Date: 2026-06-09

Transferred ownership of both Base bridge contracts from the deployer EOA to the
project multisig. The relayer assignment was left unchanged — the deployer EOA
remains the relayer (`syncOwnership` / `burn`), while the multisig now holds
`owner()` (and can rotate the relayer via `setRelayer`).

## Contracts

| Contract | Address | Previous owner | New owner |
|---|---|---|---|
| WrappedBNSv2 | `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4` | `0xd83113dCf145bF72F640DbD2141dCB9B14A53789` | `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2` |
| WrappedENS | `0xC7AFf3b228b8353d1811802F90f389815431a194` | `0xd83113dCf145bF72F640DbD2141dCB9B14A53789` | `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2` |

Relayer (unchanged on both): `0xd83113dCf145bF72F640DbD2141dCB9B14A53789`

## Transactions

| Contract | `transferOwnership` tx hash |
|---|---|
| WrappedBNSv2 | `0x7b5a11ed252d064c02f710d19f0f9218a7858ba628886f3ff4abd6cdbe243c22` |
| WrappedENS | `0x5592371a42501bac7d466cba5f0f0e579e361a33c99b5b1abd83159e7abf686a` |

## Post-transfer verification

```
WrappedBNSv2.owner()   = 0x09CbC0D92AABE6F53Ac7E84F0Ba0FbfD05eB80f2
WrappedBNSv2.relayer() = 0xd83113dCf145bF72F640DbD2141dCB9B14A53789
WrappedENS.owner()     = 0x09CbC0D92AABE6F53Ac7E84F0Ba0FbfD05eB80f2
WrappedENS.relayer()   = 0xd83113dCf145bF72F640DbD2141dCB9B14A53789
```
