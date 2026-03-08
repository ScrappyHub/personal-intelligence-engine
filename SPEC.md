# PIE Architecture Specification

Personal Intelligence Engine (PIE) is a deterministic runtime for producing verifiable AI execution packets.

The system is designed to run fully offline while generating exportable evidence artifacts.

---

# Core pipeline

PIE executes a deterministic pipeline:

```
materialize_vectors
      ↓
seal_run
      ↓
build_packet
      ↓
sign_packet
      ↓
verify_packet
      ↓
emit_receipts
```

Each stage produces verifiable artifacts.

---

# Run sealing

A run seal captures the deterministic execution environment.

Artifacts:

```
run_seal.json
seal_transcript.txt
```

These documents define the run identity and context.

---

# Packet generation

PIE builds packets following **Packet Constitution v1 Option A**.

Required files:

```
manifest.json
packet_id.txt
sha256sums.txt
payload/*
signatures/*
```

The packet represents the portable evidence bundle.

---

# Packet signing

PIE uses OpenSSH signing via `ssh-keygen`.

Signature artifacts:

```
sig_envelope.v1.json
signatures/sig_envelope.sig
```

Signatures bind the packet contents to the run identity.

---

# Verification

Verification is independent and non-mutating.

Verification checks:

```
packet_id correctness
sha256sums integrity
signature validity
manifest invariants
```

Verification output:

```
verification_result.json
```

---

# Test vectors

The system includes deterministic vector sets:

```
pos_minimal_v1
neg_manifest_contains_packet_id_v1
neg_packet_id_mismatch_v1
neg_sha256_mismatch_v1
```

These vectors validate the verifier’s correctness.

---

# Evidence artifacts

Evidence produced during execution:

```
proofs/runs/pie0/
freeze/PIE_TIER0_FREEZE_MANIFEST_v1.txt
```

These artifacts prove Tier-0 correctness.

---

# Tier-0 Definition of Done

PIE Tier-0 is considered complete when:

1. pipeline executes deterministically
2. positive vectors verify successfully
3. negative vectors fail deterministically
4. packets are independently verifiable
5. evidence artifacts are reproducible
