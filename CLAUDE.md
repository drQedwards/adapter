# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
# Build
forge build

# Test (all)
forge test

# Test (single test by name)
forge test --match-test testBindExistingHappyPathWithPerTokenApproval -vvv

# Test (single file)
forge test --match-path test/Adapter8004.t.sol -vvv

# Format
forge fmt

# Deploy (initial proxy + implementation)
cp .env.example .env   # fill in DEPLOYER_PRIVATE_KEY and RPC URLs
script/deploy.sh base  # or: mainnet | sepolia

# Deploy implementation only (for UUPS upgrade via Safe)
forge script script/DeployAdapterImplementation.s.sol --rpc-url $RPC_URL --broadcast
```

Submodules must be initialized before building on a fresh clone:

```sh
git submodule update --init --recursive
```

## Architecture

**One contract, one proxy.** The entire protocol lives in `src/Adapter8004.sol` — a UUPS-upgradeable implementation deployed behind an `ERC1967Proxy`. There are no libraries, no routers, no multi-contract call graphs. All logic paths start and end in that file.

### What the adapter does

The adapter re-routes control of an ERC-8004 identity record from the `ownerOf(agentId)` check on the registry to whoever currently holds a bound external token. The adapter owns the ERC-8004 NFT permanently; external token holders drive it through the adapter.

```
External token holder  →  Adapter8004 (proxy)  →  ERC-8004 IdentityRegistry
```

### Binding model

Every ERC-8004 `agentId` is bound once to exactly one external token coordinate `(standard, tokenContract, tokenId)`. The binding is written to `_bindings[agentId]` and never changed. A single external token may produce multiple agents (via repeated `register` calls), but each agent maps to exactly one token.

Control resolution per standard:
- **ERC-721**: `ownerOf(tokenId)` on the token contract, _or_ a hot wallet with a valid delegate.xyz v2 delegation from the owner (scoped to `keccak256("adapter8004.manage")` or an all/full delegation)
- **ERC-1155** / **ERC-6909**: any account with `balanceOf(account, tokenId) > 0` — shared control is intentional

### Two entry paths for binding

1. **`register(...)`** — caller proves control of an external token; adapter mints a new ERC-8004 agent, stores the binding, writes canonical `agent-binding` metadata (the 20-byte proxy address), and immediately clears the default ERC-8004 agent wallet (which would otherwise be set to the adapter).

2. **`bindExisting(agentId, standard, tokenContract, tokenId)`** — two-transaction flow to pull an already-minted agent into adapter management. The agent owner first calls `approve(adapter, agentId)` or `setApprovalForAll(adapter, true)` on the registry, then calls `bindExisting`. The adapter transfers the NFT to itself, stores the binding, and overwrites the `agent-binding` metadata key. Does **not** clear the agent wallet (unlike `register`).

### Counterfactual surface

Every write function has a `counterfactual*` mirror (`counterfactualRegister`, `counterfactualSetAgentURI`, etc.) that emits an event but writes no state — no ERC-8004 registry call, no SSTORE. These are gated by the same control checks as the on-chain surface. Indexers treat the latest event per `registrationHash` as authoritative.

The `registrationHash` is `keccak256(abi.encode(chainid, adapterProxy, standard, tokenContract, tokenId))`, binding the claim to a specific chain, adapter, and token.

**Breaking-change rule**: any change to the counterfactual event ABI changes `topic[0]`, which silently breaks indexers watching the old topic. Treat counterfactual event ABI changes as hard cutovers requiring a documented implementation bump.

### Reserved metadata keys

- `agent-binding` — canonical ERC-8217 binding discovery; only the adapter may write this key
- `cf-registration` — canonical-promotion back-link; reserved on the counterfactual surface only

Both are enforced by hashing the incoming key and comparing to the stored `bytes32` constant, not by string comparison.

### Name hazard in internal helpers

Two internal functions have nearly identical names but different argument types:
- `_requireNotReservedBindingKey(string calldata)` — guards one key
- `_requireNoReservedBindingKey(MetadataEntry[] memory)` — guards an array

Picking the wrong one compiles without error. Confirm the argument type before calling either.

### Admin model

The adapter owner (currently a Gnosis Safe at `0x03302Df40186D9B85faEA4fbb6cC5da028B23149`) can:
- upgrade the implementation via UUPS (`upgradeToAndCall`)
- repoint `identityRegistry` to a new registry address
- call `rewriteBindingMetadata(agentId)` to migrate legacy `agent-binding` values to the current 20-byte format

The deployer EOA (`DeployAdapterImplementation.s.sol`) deploys only the new implementation — it cannot call `upgradeToAndCall` because the proxy is owned by the Safe. The script emits a Safe Transaction Builder JSON to `deployments/` for the Safe signers to submit.

### Wallet assignment

`setAgentWallet` passes through native ERC-8004 signature checks. The signed EIP-712 payload must use the **adapter proxy address** as the `owner` field (not the external token holder), because the adapter owns the ERC-8004 NFT.

## Cross-chain name bridges

`src/bridges/` contains ERC-721 mirror contracts that let external naming systems control ERC-8004 agents. The adapter requires no changes — it sees these as standard ERC-721 bindings.

Both Base bridges share the same admin model:
- **Owner** (multisig, rotates the relayer via `setRelayer`): `0x09cbc0d92aabe6f53ac7e84f0ba0fbfd05eb80f2`
- **Relayer** (`syncOwnership` / `burn`): `0xd83113dCf145bF72F640DbD2141dCB9B14A53789`

### WrappedBNSv2 (`.btc` names on Stacks)

Mirrors BNS v2 (SIP-009) ownership from the Stacks blockchain onto EVM. A trusted off-chain relayer watches Stacks for name transfers and calls `syncOwnership(canonicalName, evmOwner)`.

- **tokenId**: `uint256(keccak256(abi.encodePacked("alice.btc")))` — deterministic, consistent across all EVM chains
- **EVM transfers blocked**: only the relayer can move ownership; `approve` and `setApprovalForAll` revert
- **Expiry/burn**: relayer calls `burn(name)` when the name lapses; any controller-gated adapter call then reverts until the name is re-registered
- **delegate.xyz** still works: the `.btc` holder can delegate a hot EVM wallet via delegate.xyz v2 without relayer involvement

Registration once the relayer has synced:
```solidity
adapter.register(
    TokenStandard.ERC721,
    address(wrappedBNSv2),
    wrappedBNSv2.nameToTokenId("alice.btc"),
    agentURI
);
```

**Deployed addresses:**
- Ethereum mainnet: `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4`
- Base: `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4`
- Arbitrum One: `0xa98741B7EE20B096a6262A705A088f8c0563Dfa4`

(Same address on all chains — the deployer EOA shared a nonce at deploy time. On mainnet and Arbitrum the contract was deployed with the multisig as `owner` from birth, so no post-deploy ownership transfer was needed.)

### WrappedENS (`.eth` names on non-mainnet chains)

Same pattern for ENS `.eth` names on chains other than Ethereum mainnet. On mainnet, ENS second-level names are already ERC-721 tokens (BaseRegistrar `0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85`) and bind directly with no wrapper needed:

```solidity
// mainnet only — no wrapper required
adapter.register(
    TokenStandard.ERC721,
    0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85,
    uint256(keccak256("alice")),   // ENS BaseRegistrar tokenId convention
    agentURI
);
```

For Base, Optimism, Sepolia, etc., deploy `WrappedENS` and point a relayer at it. `labelToTokenId(label)` matches the ENS BaseRegistrar's own `uint256(keccak256(label))` convention so tokenIds align with on-chain ENS data on mainnet.

**Deployed addresses:**
- Base: `0xC7AFf3b228b8353d1811802F90f389815431a194`
- Arbitrum One: `0xC7AFf3b228b8353d1811802F90f389815431a194`

On Arbitrum the ERC-8004 registry is present but the adapter is not yet deployed, so the bridges mirror names today; `register()` works there once an adapter proxy exists.

## Test structure

```
test/
  Adapter8004.t.sol               # Main unit tests (85 tests)
  Adapter8004.delegate.t.sol      # delegate.xyz hot/cold delegation tests
  Adapter8004.interfaces.t.sol    # Interface compliance
  DeployAdapterImplementation.t.sol
  mocks/                          # MockERC721, MockERC1155, MockERC6909, MockIdentityRegistry, MockDelegateRegistry
  security/
    Adapter8004.security.t.sol    # Access-control assertions
    Adapter8004.fuzz.t.sol        # Fuzz suite (256 runs each)
    Adapter8004.invariants.t.sol  # Property-based invariants
    Adapter8004.adversarial.t.sol # Reentrancy, malicious tokens, overflow registry
    Adapter8004.counterfactual.t.sol
    mocks/                        # Malicious token mocks (reentrant, reverting, overflow)
```

All tests use Foundry's `Test` base. The standard test setup deploys the adapter behind an `ERC1967Proxy`, a `MockIdentityRegistry`, and three mock token contracts (ERC-721/1155/6909).

## Deployments

Proxy addresses (interact with these, not the implementations):
- Mainnet: `0xde152AfB7db5373F34876E1499fbD893A82dD336`
- Base: `0x270d25D2c59A8bcA1B0f40ad95fF7806c0025c27`
- Sepolia: `0x7621630cB63a73a194f45A3E6801B8C6A7eC2f92`

ERC-8004 registry (same on Mainnet and Base): `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`  
ERC-8004 registry (Sepolia): `0x8004A818BFB912233c491871b3d84c89A494BD9e`  
delegate.xyz v2 registry (all chains): `0x00000000000000447e69651d841bD8D104Bed493`  
Admin Safe (all chains): `0x03302Df40186D9B85faEA4fbb6cC5da028B23149`

Upgrade history and Safe TX JSON payloads live in `deployments/`.
