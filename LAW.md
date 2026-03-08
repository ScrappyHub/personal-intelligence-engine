# PIE Protocol Law

This document defines **non-negotiable invariants** of the Personal Intelligence Engine.

Any implementation violating these rules is considered invalid.

---

# Packet Constitution

PIE packets follow **Packet Constitution v1 Option A**.

Required rules:

1. `manifest.json` MUST NOT contain `packet_id`
2. `packet_id.txt` MUST equal SHA256(manifest canonical bytes)
3. `sha256sums.txt` MUST be generated last
4. verification MUST NOT mutate packet contents

---

# Determinism

The pipeline MUST be deterministic.

The same inputs MUST produce identical packets.

---

# Verification independence

Verification MUST be able to run without the original runtime environment.

A verifier MUST rely only on packet contents.

---

# Evidence preservation

Evidence artifacts MUST remain immutable once generated.

Artifacts include:

```
freeze manifests
run seals
verification results
transcripts
```

---

# Standalone requirement

PIE MUST function without ecosystem dependencies.

External systems may integrate later but MUST NOT be required for correctness.

---

# Tier-0 authority

The authoritative proof of Tier-0 correctness is:

```
SELFTEST_PIE_TIER0_V1_GREEN
PIE_TIER0_FULL_GREEN_V1_OK
```
