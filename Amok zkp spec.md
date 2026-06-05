# AMOK — ZKP System Architecture & Smart Contract Spec
**Autonomous Movement Of Knowledge**  
keepAIon.com · eyedby/keepaion · v0.1

---

## Overview

AMOK is a zero-knowledge proof system that lets developers publicly signal their keepAIon pledge commitment without revealing their identity. A developer pledges, AMOK generates a ZKP, and a verifiable token is issued. The proof is: *"I signed the keepAIon pledge."* The secret is: *who.*

---

## Stack

| Layer | Technology |
|---|---|
| ZK Circuit | Noir (Aztec) — simpler DX than Circom, native Rust |
| Proof generation | Barretenberg backend (bundled with Noir) |
| Smart contract | Solidity (EVM) — Base L2 for low gas |
| Frontend | Vanilla JS + snarkjs or `@noir-lang/noir_js` |
| Storage | IPFS for proof metadata |
| Identity anchor | GitHub commit hash (public, pseudonymous) |

---

## Circuit Design (Noir)

```rust
// amok_pledge.nr
// Proves: "I know a secret that hashes to a registered commitment"
// without revealing the secret or identity

use dep::std::hash::pedersen_hash;

fn main(
    // Private inputs (never revealed)
    secret: Field,
    github_handle_hash: Field,

    // Public inputs (on-chain verifiable)
    commitment: pub Field,
    nullifier: pub Field,
    pledge_root: pub Field,
) {
    // 1. Verify commitment = hash(secret, github_handle_hash)
    let computed_commitment = pedersen_hash([secret, github_handle_hash]);
    assert(computed_commitment == commitment);

    // 2. Verify nullifier = hash(secret, 0) — prevents double-signing
    let computed_nullifier = pedersen_hash([secret, 0]);
    assert(computed_nullifier == nullifier);

    // 3. Verify pledge_root — proves membership in keepAIon merkle tree
    // (simplified — full impl uses merkle proof path)
    let computed_root = pedersen_hash([commitment, pledge_root]);
    assert(computed_root != 0); // merkle membership check
}
```

### Circuit Inputs

| Input | Type | Visibility | Description |
|---|---|---|---|
| `secret` | Field | **Private** | Developer's passphrase, hashed locally |
| `github_handle_hash` | Field | **Private** | Hash of GitHub username |
| `commitment` | Field | **Public** | `hash(secret, github_hash)` — stored on-chain |
| `nullifier` | Field | **Public** | `hash(secret, 0)` — prevents double pledging |
| `pledge_root` | Field | **Public** | Merkle root of all commitments |

---

## Smart Contract (Solidity)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// AMOK.sol — keepAIon pledge verifier
// Deploy on Base (chainId: 8453)

interface IVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) 
        external view returns (bool);
}

contract AMOK {

    // ── State ──────────────────────────────────────────────
    IVerifier public immutable verifier;
    
    bytes32 public pledgeRoot;          // Merkle root of all commitments
    uint256 public totalPledges;        // Public counter — no identities
    
    mapping(bytes32 => bool) public nullifiers;     // Spent nullifiers
    mapping(bytes32 => bool) public commitments;    // Registered commitments
    mapping(bytes32 => uint256) public tokenIds;    // commitment → token ID
    mapping(uint256 => bytes32) public tokens;      // token ID → proof hash

    // ── Events ─────────────────────────────────────────────
    event PledgeMade(uint256 indexed tokenId, bytes32 nullifier);
    event RootUpdated(bytes32 newRoot);

    // ── Constructor ────────────────────────────────────────
    constructor(address _verifier, bytes32 _initialRoot) {
        verifier = IVerifier(_verifier);
        pledgeRoot = _initialRoot;
    }

    // ── Register commitment (before proof) ─────────────────
    // Developer calls this first with their commitment (public hash)
    // No identity revealed — just a hash
    function registerCommitment(bytes32 commitment) external {
        require(!commitments[commitment], "AMOK: already registered");
        commitments[commitment] = true;
        // In production: update merkle tree off-chain, then updateRoot()
    }

    // ── Submit ZK proof and mint token ─────────────────────
    function pledge(
        bytes calldata proof,
        bytes32 commitment,
        bytes32 nullifier,
        bytes32 root
    ) external returns (uint256 tokenId) {
        // 1. Check nullifier not spent
        require(!nullifiers[nullifier], "AMOK: already pledged");
        
        // 2. Check commitment registered
        require(commitments[commitment], "AMOK: commitment unknown");
        
        // 3. Check root matches
        require(root == pledgeRoot, "AMOK: invalid root");

        // 4. Verify ZK proof
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = commitment;
        publicInputs[1] = nullifier;
        publicInputs[2] = root;
        require(verifier.verify(proof, publicInputs), "AMOK: invalid proof");

        // 5. Mark nullifier spent
        nullifiers[nullifier] = true;

        // 6. Mint token
        tokenId = ++totalPledges;
        tokens[tokenId] = nullifier;
        tokenIds[commitment] = tokenId;

        emit PledgeMade(tokenId, nullifier);
    }

    // ── Verify a token is valid ─────────────────────────────
    function verify(uint256 tokenId) external view returns (bool) {
        return tokens[tokenId] != bytes32(0);
    }

    // ── Admin: update merkle root ───────────────────────────
    function updateRoot(bytes32 newRoot) external {
        // In production: add access control (multisig or DAO)
        pledgeRoot = newRoot;
        emit RootUpdated(newRoot);
    }
}
```

---

## Frontend Flow

```javascript
// amok-client.js
import { Noir } from '@noir-lang/noir_js';
import { BarretenbergBackend } from '@noir-lang/backend_barretenberg';
import circuit from './amok_pledge.json'; // compiled circuit

export async function runAMOK(githubHandle, passphrase) {

  // 1. Hash inputs locally — nothing leaves the browser raw
  const secretBytes = new TextEncoder().encode(passphrase);
  const secretHash = await crypto.subtle.digest('SHA-256', secretBytes);
  const secret = BigInt('0x' + [...new Uint8Array(secretHash)]
    .map(b => b.toString(16).padStart(2,'0')).join(''));

  const handleBytes = new TextEncoder().encode(githubHandle.toLowerCase());
  const handleHash = await crypto.subtle.digest('SHA-256', handleBytes);
  const githubHandleHash = BigInt('0x' + [...new Uint8Array(handleHash)]
    .map(b => b.toString(16).padStart(2,'0')).join(''));

  // 2. Compute public inputs
  const commitment = pedersen([secret, githubHandleHash]); // use noble-curves
  const nullifier  = pedersen([secret, 0n]);

  // 3. Generate ZK proof (runs in browser via WASM)
  const backend = new BarretenbergBackend(circuit);
  const noir = new Noir(circuit, backend);

  const { proof, publicInputs } = await noir.generateFinalProof({
    secret:              secret.toString(),
    github_handle_hash:  githubHandleHash.toString(),
    commitment:          commitment.toString(),
    nullifier:           nullifier.toString(),
    pledge_root:         await fetchCurrentRoot(), // from contract
  });

  // 4. Submit to contract
  const tx = await amokContract.pledge(proof, commitment, nullifier, pledgeRoot);
  const receipt = await tx.wait();
  const tokenId = receipt.events[0].args.tokenId;

  return { tokenId, proof, commitment, nullifier };
}
```

---

## Deployment Plan

### Phase 1 — Testnet (now)
- Deploy on **Base Sepolia**
- Circuit compiled with Noir 0.30+
- Frontend at `amok.keepaion.com`
- Proof generation: browser WASM (~2-4s)

### Phase 2 — Mainnet
- Deploy on **Base** (low gas, Coinbase-backed, dev-friendly)
- Merkle tree managed off-chain, root pushed on-chain weekly
- IPFS storage for proof metadata
- ENS subdomain: `amok.keepaion.eth`

### Phase 3 — Soulbound Token (SBT)
- Non-transferable ERC-721 variant
- Token metadata: pledge date, AMOK version, proof hash
- No wallet address in metadata — only nullifier

---

## Security Considerations

| Risk | Mitigation |
|---|---|
| Double-pledge | Nullifier stored on-chain — same secret = same nullifier = rejected |
| Identity leak | GitHub handle is private input, never on-chain |
| Proof forgery | Barretenberg PLONK proof — computationally infeasible to forge |
| Commitment grinding | Pedersen hash — preimage resistance |
| Front-running | Commitment registered before proof — two-step prevents front-run |

---

## Repo Structure

```
eyedby/keepaion
├── circuits/
│   └── amok_pledge/
│       ├── src/main.nr          ← Noir circuit
│       └── Nargo.toml
├── contracts/
│   ├── AMOK.sol                 ← Main verifier contract  
│   ├── AMOKToken.sol            ← SBT variant
│   └── test/
│       └── AMOK.test.ts
├── frontend/
│   ├── amok-client.js           ← Browser proof generation
│   └── index.html               ← keepaion.com pledge page
├── scripts/
│   ├── deploy.ts                ← Hardhat deploy
│   └── merkle.ts                ← Merkle tree management
└── README.md
```

---

## Quick Start

```bash
# Install Noir
curl -L https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash
noirup

# Compile circuit
cd circuits/amok_pledge
nargo compile

# Generate verifier contract
nargo codegen-verifier

# Run tests
cd ../../contracts
npx hardhat test

# Deploy to Base Sepolia
npx hardhat run scripts/deploy.ts --network base-sepolia
```

---

## Badge README Snippet

```markdown
[![AMOK verified](https://keepaion.com/amok-badge.svg)](https://keepaion.com)
<!-- we thought this through -->
```

---

*AMOK v0.1 · keepAIon.com · eyedby/keepaion · building by builders*
