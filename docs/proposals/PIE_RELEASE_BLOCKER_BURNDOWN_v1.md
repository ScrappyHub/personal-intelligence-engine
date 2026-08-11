# PIE Release-Blocker Burn-Down Plan v1

Status: implementation/release-gate proposal. Does **not** redefine PIE's canonical role,
schemas, receipt contracts, or determinism law. Sequences the desktop/hosted release blockers
listed in `docs/proposals/PIE_STATE_INTEGRITY_HARDENING.md` into ordered, testable work items.

## Governing rule (from PIE LAW + the state-integrity evidence rule)

No item is "done" until it has **all three**: a repeatable **positive test**, a **negative
test** (proving the failure mode is actually caught), and a **durable receipt** written under
`proofs/` or `runs/`. A successful package, launch, or single model response is insufficient.
Each item below names its Definition of Done (DoD) in those terms.

## Sequencing rationale

State integrity is the foundation: signing, soak, drift, and rollback all assume a stable,
migratable state layer. So Phase 1 hardens persistence and fault behavior first, Phase 2 proves
durability over time and process/power faults, Phase 3 handles the real-model semantic layer and
user-facing memory controls, Phase 4 is desktop distribution, and Phase 5 gates hosting. Phases
are ordered; items within a phase can parallelize.

---

## Phase 1 — State layer & migrations (foundation)

- **B1. Versioned schema migrations for every persistent schema** (not only desktop workspace
  relocation).
  - FOUNDATION LANDED 2026-08-11: `schemas/PIE_SCHEMA_REGISTRY.v1.json` enumerates every
    persistent schema + current version; `scripts/_lib_pie_migrations_v1.ps1` provides the
    fail-closed version guard (unknown schema and newer-than-known both rejected — no silent
    downgrade/drift) + an idempotent migration runner (registry empty; all schemas at current);
    `scripts/_selftest_pie_migrations_v1.ps1` proves it (green token
    `SELFTEST_PIE_MIGRATIONS_V1_GREEN`), wired into verify-all as `state:migrations`.
  - REMAINING: register a real forward migration + old→new fixture the first time any schema goes
    to v2 (`pie.exec.policy` is already v2 — backfill its v1→v2 migration + fixture as the first
    concrete case); add per-schema DoD tests and receipts.
  - DoD: per-schema migration test (old fixture → migrated), negative test (tampered/unknown
    version fails closed — DONE at framework level), receipt `runs/migrations_selftest/<ts>.json`.
- **B2. Disk-full / permission-loss / AV-lock / interrupted-write handling** around every
  multi-file state transition (session write, memory write, backup export, desktop sync).
  - FOUNDATION LANDED 2026-08-11: `scripts/_lib_pie_atomic_v1.ps1` provides `PIE_WriteFileAtomic`
    (temp-in-same-dir → flush-to-disk → atomic replace; original preserved + no temp residue on
    failure) and `PIE_ReadNdjsonSafe` (torn trailing-line detection for interrupted appends).
    `scripts/_selftest_pie_atomic_write_v1.ps1` proves new/overwrite/locked-target-failure/
    torn-tail (green token `SELFTEST_PIE_ATOMIC_WRITE_V1_GREEN`), wired into verify-all as
    `state:atomic_write`.
  - REMAINING: route existing writers (`NL_WriteUtf8NoBomLf`, ledger/receipt appends, session +
    memory writes, backup export, desktop sync) through the atomic primitive, one state path at a
    time with re-verification; add real disk-full/permission-loss/AV-lock injection per transition.
  - DoD: fault-injection test per transition simulating each failure; negative test proves no
    partial/torn state is accepted (DONE at primitive level); receipt per scenario.

## Phase 2 — Durability under faults & time

- **B3. Process-kill and power-loss fault injection** around each multi-file transition (kill
  between file N and N+1; assert atomic recovery or clean fail).
  - DoD: kill-at-each-step harness, recovery positive test, corruption-detected negative test,
    NDJSON receipt log.
- **B4. Multi-hour / multi-day restart + soak** across multiple repositories and sessions
  (concurrent chat + memory + backup under churn).
  - DoD: scheduled soak runner, pass criteria (zero integrity failures, zero cross-scope
    bleed), durable soak receipt with timings.

## Phase 3 — Model semantics & user memory controls

- **B5. Real-model drift evaluation across every supported model tier.** Hashes prevent state
  substitution but not model forgetting. Define a fact-retention/consistency eval per tier.
  - DoD: eval set + scoring, per-tier baseline receipt, regression gate on re-run.
- **B6. Deterministic conversation compaction / pinned-fact behavior** when a chat exceeds the
  active context window.
  - DoD: compaction spec, positive test (pinned facts survive), negative test (silent fact loss
    is detected/flagged), receipt.
- **B7. User memory controls**: inspect, provenance, accept, correct, forget, project-scope.
  - DoD: per-control positive + negative test (e.g., "forget" leaves no residue), receipts;
    surfaced in CLI + workbench.

## Phase 4 — Desktop distribution

- **B8. Update rollback** preserves and reopens the same state without downgrade ambiguity.
  - DoD: upgrade→rollback test reopening identical verified state; negative test rejects
    ambiguous downgrade; receipt.
- **B9. Installer / uninstaller, Windows signing, SmartScreen reputation, supported-OS matrix,
  accessibility, completed visual browser pass.**
  - DoD: signed-artifact validation, clean install/uninstall test on each supported OS,
    accessibility checklist, receipts.

## Phase 5 — Hosted gateway (gated last)

- **B10. Cross-machine encrypted backup v2**: explicit repository-path/model migration + a
  reviewed key-recovery design. Silent rebinding stays forbidden.
  - DoD: cross-machine restore test with explicit migration, negative test blocks silent
    rebinding, key-recovery design doc + receipt.
- **B11. Hosted auth, tenant isolation, repository import, secret handling, quotas, deletion,
  audit evidence** before any user data is hosted (implements
  `workbench/contracts/PIE_HOSTED_GATEWAY.v1.json`).
  - DoD: isolation test (tenant A cannot read B), auth/quota/deletion tests, audit-trail
    receipts.

---

## Engine adapter track (parallel to the phases above)

Not a desktop/hosted blocker, but tracked here for completeness. Status ladder:
`scaffold → preview → ready`.

All three real adapters now have an authored certification trio (host/dir-unavailable fails
closed with no stub fallback + no ledger write; unsealed model rejected; real non-stub generation
ledgered). Green token flips status; do not mark ready from inspection.

- `stub` — ready (default; frozen Tier-0 vectors).
- `ollama` — preview; test `scripts/_selftest_pie_engine_ollama_v1.ps1`
  (`SELFTEST_PIE_ENGINE_OLLAMA_V1_GREEN`). Run on Windows with Ollama up + a sealed/pulled
  `-ModelId` → preview → ready.
- `llamacpp` — scaffold; test `scripts/_selftest_pie_engine_llamacpp_v1.ps1`
  (`SELFTEST_PIE_ENGINE_LLAMACPP_V1_GREEN`). Run with a llama.cpp server up + sealed/served
  `-ModelId` → scaffold → preview → ready.
- `onnx` — scaffold; test `scripts/_selftest_pie_engine_onnx_v1.ps1`
  (`SELFTEST_PIE_ENGINE_ONNX_V1_GREEN`) + sealed fixture `registry/models/pie-onnx-fixture`.
  Negative + binding run with no model present; drop a real onnxruntime-genai export into the
  fixture `onnx/` dir for the positive check → scaffold → preview → ready.
- `vLLM` — deferred (advanced/optional GPU-server HTTP adapter; off the offline-first-Windows path).

## Progress tracking

Recommend a checklist ledger at `docs/wbs/PIE_RELEASE_BLOCKER_LEDGER_v1.md` updated only when an
item reaches full DoD (positive + negative + receipt), mirroring the discipline that produced the
Tier-0 freeze. Do not mark items green from inspection alone.
