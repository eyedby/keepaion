# AMOK
**Autonomous Movement Of Knowledge**  
Zero-knowledge proof layer for the keepAIon developer pledge.

> *You signed. We know. Nobody else does.*

[![keepAIon](https://keepaion.com/badge.svg)](https://keepaion.com)
<!-- we thought this through -->

---

## What it does

AMOK lets developers publicly signal their [keepAIon](https://keepaion.com) pledge commitment **without revealing their identity**.

A developer pledges → AMOK generates a ZKP → a verifiable token is issued.

The proof: *"I signed the keepAIon pledge."*  
The secret: *who.*

---

## Stack

| Layer | Tech |
|---|---|
| ZK Circuit | [Noir](https://noir-lang.org) (Aztec) |
| Proof backend | Barretenberg (UltraPlonk) |
| Smart contracts | Solidity on [Base](https://base.org) |
| Frontend | Vanilla JS + `@noir-lang/noir_js` |
| Token | Soulbound ERC-721 |

---

## Quick Start

### Prerequisites
- [Noir](https://noir-lang.org) >= 0.30 — `noirup`
- Node.js >= 18
- A wallet with Base Sepolia ETH

### Install

```bash
git clone https://github.com/eyedby/keepaion
cd keepaion/amok
npm install
```

### Build & test the circuit

```bash
npm run circuit:build   # compile Noir circuit
npm run circuit:test    # run circuit tests
npm run circuit:verify  # generate Solidity verifier
```

### Run contract tests

```bash
npm run compile
npm run test
```

### Deploy to Base Sepolia

```bash
export PRIVATE_KEY=0x...
npm run deploy:testnet
```

### Deploy to Base Mainnet

```bash
export PRIVATE_KEY=0x...
export BASESCAN_API_KEY=...
npm run deploy:mainnet
```

---

## How it works

```
Developer
    │
    ├─ 1. Hash(passphrase + githubHandle) → commitment
    │       (computed locally, never transmitted raw)
    │
    ├─ 2. registerCommitment(commitment) → on-chain
    │       (no identity revealed — just a field element)
    │
    ├─ 3. Generate ZK proof in browser (WASM, ~3s)
    │       Private: secret, githubHandleHash
    │       Public:  commitment, nullifier, merkleRoot
    │
    └─ 4. pledge(proof, commitment, nullifier, root) → AMOK token minted
                tokenId issued — no wallet address in metadata
```

---

## Pledge Flow (User-Facing)

1. Visit [keepaion.com](https://keepaion.com)
2. Enter GitHub handle + passphrase
3. Hit **Run AMOK**
4. Proof generates in browser (~3s)
5. Two transactions: `registerCommitment` + `pledge`
6. Token minted — download badge, add to README

---

## Security

| Risk | Mitigation |
|---|---|
| Double-pledge | Nullifier stored on-chain — same secret = rejected |
| Identity leak | GitHub handle is private input, never on-chain |
| Proof forgery | Barretenberg UltraPlonk — computationally infeasible |
| Front-running | Two-step commit-reveal pattern |

---

## Repo Structure

```
amok/
├── circuits/
│   └── amok_pledge/
│       ├── src/main.nr        ← Noir ZK circuit
│       └── Nargo.toml
├── contracts/
│   ├── AMOK.sol               ← Main verifier + pledge logic
│   ├── AMOKToken.sol          ← Soulbound ERC-721
│   └── test/AMOK.test.ts
├── frontend/
│   └── amok-client.js         ← Browser proof generation
├── scripts/
│   ├── deploy.ts              ← Hardhat deploy
│   └── merkle.ts              ← Merkle tree management
├── hardhat.config.ts
└── package.json
```

---

## Add the badge

```markdown
[![AMOK verified](https://keepaion.com/amok-badge.svg)](https://keepaion.com)
<!-- we thought this through -->
```

---

*keepAIon.com · eyedby/keepaion · building by builders*
# keepaion
tech naturally extends into the AI domain :AI model licensing / provenance
AMOK is the AI. The eye sees everything, the ZKP proves everything, and nobody knows who did it. Let's build it.
The flow: paste your GitHub + a secret passphrase → AMOK generates a ZK proof locally (witness, nullifier, merkle root, proof hash) → you get a unique token ID like AMOK-3F9A12 and a downloadable SVG. The passphrase never leaves the browser.
