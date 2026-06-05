// amok-client.js
// Browser-side AMOK proof generation
// Runs entirely in-browser via WASM — nothing private leaves the device
//
// eyedby/keepaion · keepAIon.com · v0.1
//
// Usage:
//   import { runAMOK, registerAndPledge } from './amok-client.js';
//
// Dependencies (load via CDN or bundle):
//   @noir-lang/noir_js
//   @noir-lang/backend_barretenberg
//   ethers v6

import { Noir }                   from '@noir-lang/noir_js';
import { BarretenbergBackend }     from '@noir-lang/backend_barretenberg';
import { ethers }                  from 'ethers';

// ── Config ────────────────────────────────────────────────────
const CONFIG = {
    contractAddress: '',         // set after deployment
    rpcUrl:          'https://sepolia.base.org',
    chainId:         84532,      // Base Sepolia (change to 8453 for mainnet)
    circuitPath:     '/circuit/amok_pledge.json',
};

// ── ABI (minimal) ─────────────────────────────────────────────
const AMOK_ABI = [
    'function registerCommitment(bytes32 commitment) external',
    'function pledge(bytes calldata proof, bytes32 commitment, bytes32 nullifier, bytes32 root) external returns (uint256)',
    'function pledgeRoot() external view returns (bytes32)',
    'function totalPledges() external view returns (uint256)',
    'function isValid(uint256 tokenId) external view returns (bool)',
];

// ── Hash helpers (Pedersen via Barretenberg) ──────────────────
// Note: In production use @aztec/bb.js for proper Pedersen hash
// This uses SHA-256 as a placeholder until BB wasm is loaded
async function hashToField(data) {
    const bytes  = new TextEncoder().encode(data);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const hex    = [...new Uint8Array(digest)]
        .map(b => b.toString(16).padStart(2, '0')).join('');
    // Reduce mod BN254 scalar field for Noir compatibility
    return BigInt('0x' + hex) % BigInt(
        '0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001'
    );
}

// ── Core: generate ZK proof in browser ───────────────────────
export async function generateAMOKProof(githubHandle, passphrase, merkleProof) {
    // 1. Hash private inputs locally
    const secret            = await hashToField(passphrase);
    const githubHandleHash  = await hashToField(githubHandle.toLowerCase().trim());

    // 2. Compute public inputs
    //    In production: use proper Pedersen from @aztec/bb.js
    const commitment = await hashToField(`commitment:${secret}:${githubHandleHash}`);
    const nullifier  = await hashToField(`nullifier:${secret}:0`);

    // 3. Load compiled circuit
    const circuitJson = await fetch(CONFIG.circuitPath).then(r => r.json());

    // 4. Generate proof (runs in WASM, ~2-4 seconds)
    const backend = new BarretenbergBackend(circuitJson, { threads: 4 });
    const noir    = new Noir(circuitJson, backend);

    const { proof, publicInputs } = await noir.generateFinalProof({
        secret:              secret.toString(),
        github_handle_hash:  githubHandleHash.toString(),
        path_indices:        merkleProof.pathIndices,
        hash_path:           merkleProof.hashPath,
        commitment:          commitment.toString(),
        nullifier:           nullifier.toString(),
        pledge_root:         merkleProof.root,
    });

    return {
        proof,
        commitment: '0x' + commitment.toString(16).padStart(64, '0'),
        nullifier:  '0x' + nullifier.toString(16).padStart(64, '0'),
        root:       merkleProof.root,
        publicInputs,
    };
}

// ── Full flow: register + prove + submit ─────────────────────
export async function runAMOK(githubHandle, passphrase, onStatus) {
    const provider = new ethers.BrowserProvider(window.ethereum);
    const signer   = await provider.getSigner();
    const contract = new ethers.Contract(CONFIG.contractAddress, AMOK_ABI, signer);

    try {
        // Step 1: Get current merkle root from contract
        onStatus?.('Fetching pledge tree root...');
        const pledgeRoot = await contract.pledgeRoot();

        // Step 2: Get merkle proof from API (your backend manages the tree)
        onStatus?.('Fetching merkle proof...');
        const secret           = await hashToField(passphrase);
        const githubHandleHash = await hashToField(githubHandle.toLowerCase().trim());
        const commitment       = await hashToField(`commitment:${secret}:${githubHandleHash}`);
        const commitmentHex    = '0x' + commitment.toString(16).padStart(64, '0');

        // Register commitment first (two-step prevents front-running)
        onStatus?.('Registering commitment...');
        const regTx = await contract.registerCommitment(commitmentHex);
        await regTx.wait();

        // Fetch merkle proof from your backend after registration
        const merkleRes  = await fetch(`/api/merkle-proof?commitment=${commitmentHex}`);
        const merkleProof = await merkleRes.json();

        // Step 3: Generate ZK proof in browser
        onStatus?.('Generating zero-knowledge proof (this takes a few seconds)...');
        const proofData = await generateAMOKProof(githubHandle, passphrase, merkleProof);

        // Step 4: Submit proof to contract
        onStatus?.('Submitting proof on-chain...');
        const pledgeTx = await contract.pledge(
            proofData.proof,
            proofData.commitment,
            proofData.nullifier,
            proofData.root,
        );
        const receipt = await pledgeTx.wait();

        // Extract token ID from event
        const event   = receipt.logs.find(l => l.eventName === 'PledgeMade');
        const tokenId = event?.args?.tokenId?.toString() ?? '?';

        onStatus?.(`✓ AMOK token minted — ID: ${tokenId}`);
        return { tokenId, ...proofData };

    } catch (err) {
        console.error('AMOK error:', err);
        throw err;
    }
}

// ── Read: verify a token ──────────────────────────────────────
export async function verifyToken(tokenId) {
    const provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
    const contract = new ethers.Contract(CONFIG.contractAddress, AMOK_ABI, provider);
    return contract.isValid(tokenId);
}

// ── Read: total pledge count ──────────────────────────────────
export async function getTotalPledges() {
    const provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
    const contract = new ethers.Contract(CONFIG.contractAddress, AMOK_ABI, provider);
    return (await contract.totalPledges()).toString();
}
