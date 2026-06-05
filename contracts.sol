// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────
//  AMOK.sol — keepAIon pledge ZK verifier
//  Autonomous Movement Of Knowledge
//
//  eyedby/keepaion · keepAIon.com · v0.1
//  Deploy on Base (chainId: 8453) or Base Sepolia (84532)
// ─────────────────────────────────────────────────────────────

interface IUltraVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs)
        external view returns (bool);
}

contract AMOK {

    // ── Immutables ────────────────────────────────────────────
    IUltraVerifier public immutable verifier;

    // ── State ─────────────────────────────────────────────────
    bytes32 public pledgeRoot;
    uint256 public totalPledges;
    address public owner;

    mapping(bytes32 => bool)    public nullifiers;   // spent nullifiers
    mapping(bytes32 => bool)    public commitments;  // registered commitments
    mapping(uint256 => bytes32) public tokens;        // tokenId → nullifier
    mapping(bytes32 => uint256) public tokenByCommitment;

    // ── Events ────────────────────────────────────────────────
    event CommitmentRegistered(bytes32 indexed commitment);
    event PledgeMade(uint256 indexed tokenId, bytes32 indexed nullifier);
    event RootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);

    // ── Errors ────────────────────────────────────────────────
    error AlreadyRegistered();
    error AlreadyPledged();
    error CommitmentUnknown();
    error InvalidRoot();
    error InvalidProof();
    error Unauthorized();

    // ── Constructor ───────────────────────────────────────────
    constructor(address _verifier, bytes32 _initialRoot) {
        verifier   = IUltraVerifier(_verifier);
        pledgeRoot = _initialRoot;
        owner      = msg.sender;
    }

    // ── Step 1: Register commitment ───────────────────────────
    // Developer calls this with commitment = pedersen(secret, githubHash)
    // No identity revealed — just a field element hash
    function registerCommitment(bytes32 commitment) external {
        if (commitments[commitment]) revert AlreadyRegistered();
        commitments[commitment] = true;
        emit CommitmentRegistered(commitment);
    }

    // ── Step 2: Submit ZK proof and receive token ─────────────
    // proof     — Barretenberg PLONK proof bytes
    // commitment — public: hash(secret, githubHash)
    // nullifier  — public: hash(secret, 0)
    // root       — public: current merkle root
    function pledge(
        bytes   calldata proof,
        bytes32          commitment,
        bytes32          nullifier,
        bytes32          root
    ) external returns (uint256 tokenId) {
        if (nullifiers[nullifier])          revert AlreadyPledged();
        if (!commitments[commitment])       revert CommitmentUnknown();
        if (root != pledgeRoot)             revert InvalidRoot();

        // Verify ZK proof — public inputs order must match circuit
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = commitment;
        publicInputs[1] = nullifier;
        publicInputs[2] = root;

        if (!verifier.verify(proof, publicInputs)) revert InvalidProof();

        // Mark nullifier spent — prevents double pledge
        nullifiers[nullifier] = true;

        // Issue token
        tokenId = ++totalPledges;
        tokens[tokenId]              = nullifier;
        tokenByCommitment[commitment] = tokenId;

        emit PledgeMade(tokenId, nullifier);
    }

    // ── Read: verify a token exists ──────────────────────────
    function isValid(uint256 tokenId) external view returns (bool) {
        return tokens[tokenId] != bytes32(0);
    }

    // ── Admin: update merkle root (add new commitments) ───────
    // In production: replace owner with multisig or DAO vote
    function updateRoot(bytes32 newRoot) external {
        if (msg.sender != owner) revert Unauthorized();
        emit RootUpdated(pledgeRoot, newRoot);
        pledgeRoot = newRoot;
    }

    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        owner = newOwner;
    }
}
