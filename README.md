# Personal Intelligence Engine (PIE)

Personal Intelligence Engine (PIE) is a **Tier-0 standalone offline-first personal AI runtime**.

PIE deterministically produces **exportable AI run packets** that can be independently verified anywhere without relying on a central service.

The project focuses on **local AI execution, sealed evidence generation, and deterministic verification**.

---

# What this project is to spec

PIE is designed as a **standalone personal AI runtime instrument**.

Its guarantees:

• local-first execution
• deterministic run sealing
• cryptographically verifiable export packets
• independent verification
• reproducible test vectors
• offline operation

PIE intentionally **does not require cloud infrastructure** to prove correctness.

---

# Current canonical state

PIE Tier-0 standalone pipeline is **FULL_GREEN**.

Authoritative tokens proving this state:

```
SELFTEST_PIE_TIER0_V1_GREEN
PIE_TIER0_FULL_GREEN_V1_OK
```

This means the system can:

1. materialize deterministic vectors
2. seal a run
3. build a Packet Constitution v1 Option A packet
4. sign the packet
5. independently verify the packet
6. pass positive vectors
7. reject negative vectors deterministically

---

# Packet law

PIE uses **Packet Constitution v1 Option A**.

Required invariants:

```
manifest.json must NOT contain packet_id
packet_id.txt = SHA256(canonical manifest bytes)
sha256sums.txt generated LAST
verification is non-mutating
```

---

# Authoritative scripts

The following scripts define the Tier-0 pipeline:

```
scripts\_RUN_pie_tier0_full_green_v1.ps1
scripts\_selftest_pie_tier0_v1.ps1
scripts\pie_build_packet_optionA_v1.ps1
scripts\pie_verify_packet_optionA_v1.ps1
scripts\pie_run_packet_sign_v1.ps1
scripts\pie_materialize_vectors_v1.ps1
```

---

# Repository evidence artifacts

```
freeze\PIE_TIER0_FREEZE_MANIFEST_v1.txt
proofs\runs\pie0\
test_vectors\
docs\wbs\PIE_WBS_PROGRESS_LEDGER_v1.md
```

These artifacts prove the first successful standalone Tier-0 pipeline execution.

---

# Design philosophy

PIE follows a strict design philosophy:

• **standalone first**
• **deterministic verification**
• **offline reproducibility**
• **cryptographic proof of execution**

Ecosystem integrations are intentionally **deferred** until the standalone instrument is stable.

---

# Next locked work

Upcoming deterministic work:

• clean public repo surface
• tighten documentation for external readers
• refine freeze and evidence bundle format
• document offline runtime impact metrics
• prepare a clearer public release pack

---

# License

License to be determined.

The project is currently focused on stabilizing the standalone runtime.
