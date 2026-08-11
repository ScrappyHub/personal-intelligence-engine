# PIE WBS + Progress Ledger (Tier-0 Standalone) v1

> **STATUS UPDATE — 2026-08-10 (supersedes the 2026-02-21 snapshot below).**
> The 2026-02-21 figures ("~35% spec / ~20% readiness, not yet end-to-end green, blocked on
> signing + runner quoting") are **stale** and retained only for history. They are contradicted
> by later verifiable evidence:
> - First real FULL_GREEN standalone Tier-0 pipeline frozen 2026-03-08
>   (`freeze/PIE_TIER0_FREEZE_MANIFEST_v1.txt`, tokens `SELFTEST_PIE_TIER0_V1_GREEN`,
>   `PIE_TIER0_FULL_GREEN_V1_OK`). The signing + runner-quoting blockers listed at the bottom of
>   this file are **resolved**.
> - `pie doctor` (`runs/doctor/latest.json`, 2026-08-10): overall **attention**,
>   `release_ready: false`. Ready: cli, memory, models, runtime, workbench, backups, haai.
>   Attention: conversations, desktop. Contract-only: hosted. Unavailable: integrations.
> - Backend engine layer added 2026-08-10 (`engine/`, opt-in `pie_run_v1 -Backend ollama`);
>   default `stub` path unchanged. See `docs/PIE_AUDIT_2026-08-10.md` for the full findings and
>   the current open-gap list.
>
> Net current position: the **standalone Tier-0 instrument is green and usable**; the **desktop
> and hosted release tracks are not**, per the blocker set in
> `docs/proposals/PIE_STATE_INTEGRITY_HARDENING.md`. Refresh or archive the historical snapshot
> below in a future canonical pass.

---

WHAT THIS PROJECT IS TO SPEC
- PIE is a Tier-0 Standalone offline-first personal AI engine runtime.
- It must stand alone (no ecosystem integrations required) until proven and built.
- It produces deterministic run export packets: seal -> build -> sign -> verify -> receipts.
- Transport: Packet Constitution v1 Option A (manifest without packet_id; packet_id.txt derived; sha256sums last; verify non-mutating).

Progress snapshot (2026-02-21)
- Spec completeness: ~35%
- Standalone instrument readiness: ~20%
- Current state: structurally formed, not yet end-to-end green due to signing + runner quoting failures.

WBS Domains (A-H) with required proofs

### A) Repo determinism + hygiene
- [ ] A1 Deterministic rule enforced: write-to-file + parse-gate + powershell.exe -File only
  - Proof: scripts/_scratch runners + this ledger committed
- [ ] A2 UTF-8 no BOM + LF invariant verified for generated artifacts
  - Proof: proofs/audit/utf8_lf_check.txt

### B) Run model: seal -> build -> verify (standalone)
- [ ] B1 Seal creates run folder deterministically (run_id rules documented)
  - Proof: docs/SPEC_RUN_MODEL.md + proofs/runs/pie0/seal_transcript.txt
- [ ] B2 Build emits packet_id + run_id + absolute packet path
  - Proof: proofs/runs/pie0/build_transcript.txt
- [ ] B3 Verify produces deterministic non-mutating verification transcript+receipt
  - Proof: proofs/runs/pie0/verify_transcript.txt + proofs/runs/pie0/verify_receipt.json

### C) Signing reliability (NO REPEAT CHASE)
- [ ] C1 signer uses non-terminating capture so stderr "Signing file ..." can never throw
  - Proof: scripts/pie_run_packet_sign_v1.ps1 contains sentinel + sign transcript
- [ ] C2 signer gates on ExitCode and includes stdout+stderr in failure message
  - Proof: negative vector + transcript showing captured output

### D) Packet Constitution v1 Option A compliance
- [ ] D1 PacketId = SHA-256(canonical manifest-without-id bytes) locked
  - Proof: docs/PACKET_SPEC_PIE.md + test_vectors/**/expected_packet_id.txt
- [ ] D2 sha256sums generated LAST; verifier never mutates packet
  - Proof: verify transcript shows read-only behavior

### E) Offline spin-up impact goal (water waste reduction)
- [ ] E1 Offline runtime plan documented (device reqs, pinned models, offline inference path)
  - Proof: docs/SPEC_OFFLINE_RUNTIME.md
- [ ] E2 "cloud avoided" metric defined (requests avoided, kWh proxy, time)
  - Proof: docs/SPEC_IMPACT_METRICS.md

### F) Golden vectors + selftests
- [ ] F1 Minimal packet vector committed with expected packet_id + sha256sums
  - Proof: test_vectors/** + proofs/runs/pie0/golden_verify.txt
- [ ] F2 Deterministic replay rules documented (only claim replay when pinned inputs/versions/env)
  - Proof: docs/SPEC_REPLAY_STRENGTH.md

### G) Audit / evidence discipline
- [ ] G1 Every repair has: patch script, backup path, transcript, and receipt line
  - Proof: proofs/audit/patch_log.ndjson (append-only)

### H) Deferred ecosystem (Tier-2) - NOT REQUIRED YET
- [ ] H1 NFL duplication (deferred)
- [ ] H2 WatchTower verification (deferred)

Current blocker list
- Runner parse failures caused by invalid C-style escaping sequences in generated PowerShell source.
- Signer path must never allow ssh-keygen stderr to become a terminating error.

