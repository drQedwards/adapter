# Live end-to-end run — all chains

Date: 2026-06-09
Demo name: `process-demo.btc` (clearly-labeled test name; not a real third-party name)
Relayer / name owner: `0xd83113dCf145bF72F640DbD2141dCB9B14A53789`

Local validation before the live runs: `forge build` clean, `forge test` = 235 passing.

## Base — full lifecycle ✅

| Step | Result |
|---|---|
| `syncOwnership` (mint) | tx `0x45283d4dbddb165511d1f4e129a19a71baaea3d6f2174f6aa4c1a859f83c5a35` |
| EVM transfer blocked | `transferFrom` reverts `EVMTransfersBlocked` (`0xe406f414`) |
| `register` agent | tx `0xb0f91f724ec273cb5267c624194cd11c8d53dbe06c56e141ce2df5ca36a3d9f1`, **agentId 54943** |
| Control resolution | `isController(owner)=true`, `isController(stranger)=false` |
| 8004 NFT custody | held by adapter `0x270d25…` (cannot be extracted) |
| `setAgentURI` | tx `0xe6a4f6fd232295291de29cb9030a2d8d09fda40adc17e3ffb02e85c528591363` |

## Ethereum mainnet — full lifecycle ✅

| Step | Result |
|---|---|
| `syncOwnership` (mint) | tx `0xae5f9174c52aa129a948d12edc173364afce66dae67a6cd8be039fcf37da4dc5` (97,202 gas) |
| `ownerOf` after sync | `0xd83113…3789` ✓ |
| EVM transfer blocked | `transferFrom` reverts `0xe406f414` ✓ |
| `register` agent | tx `0xfd878df95480ba1cfee90265e309cf30941425d868000489cb226db9dc639a07` (245,448 gas), **agentId 34347** |
| Control resolution | `isController(owner)=true`, `isController(stranger)=false` ✓ |
| 8004 NFT custody | held by adapter `0xde152AfB7…` (cannot be extracted) ✓ |

Note: register was deferred on 2026-06-09 due to gas spike (0.72 gwei). Completed 2026-06-10 at 0.12 gwei after relayer top-up from `0xf24bd41f1a53aa8c2498026e507da6906bc54ba3`.

## Arbitrum One — bridge mirror only ✅ (register unavailable)

| Step | Result |
|---|---|
| `syncOwnership` (mint) | tx `0x62a1ddf80bd5c547c0c8f8748b67d90102fd5955329209a072a3ca6d4b4fdcad` (100,724 gas) |
| `ownerOf` / `nameOf` | `0xd83113…3789` / `"process-demo.btc"` ✓ |
| EVM transfer blocked | `transferFrom` reverts `0xe406f414` ✓ |
| `register` | **unavailable** — no Adapter8004 proxy on Arbitrum (the ERC-8004 registry `0x8004A1…` is present; only the adapter is missing). |

To enable agents on Arbitrum: deploy an Adapter8004 proxy there, then `register` works
against the existing registry and the already-deployed bridges.
