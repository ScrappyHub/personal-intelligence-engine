# PIE State-Integrity Line — Session Cap & Freeze (2026-08-12)

This document records what was sealed in this line of development, **why work was capped here**, and
the deeper Phase-1 tranche that comes next. It accompanies the freeze manifest
`freeze/PIE_STATE_INTEGRITY_FREEZE_v1.json` (sealed only when `pie verify-full` is green).

Sealed at git HEAD `75a7e5c` (see the freeze manifest for the live-verified HEAD).

## What was sealed

Verified green via one command, `pie verify-full` (engines + Tier-0 + state + session recovery +
backup + fault-injected soak):

- **Engine adapters** — `ollama` (certified with real generation), `llama.cpp` + `onnx` (opt-in,
  tested to preview/scaffold), a single shared persona (`engine/PIE_PERSONA.v1.txt`) enforced across
  all backends and across local vs. hosted, with the default deterministic `stub` path byte-identical.
- **State-integrity foundations** — B1 schema-version guard + migration framework; B2 atomic writes;
  B3 write-ahead transactions; B4 soak/restart harness; B6 deterministic compaction with pinned-fact
  retention. Each has a fail-closed test wired into `verify-engines`.
- **Real crash-atomic adoptions on every high-stakes state path** — run-seal (ledger + artifacts),
  session-turn append (conversation + transcript, with roll-forward recovery on load), and backup
  export (encrypt → verify → atomic promote). Proven under a fault-injected soak (10/10 turns crashed
  mid-write and recovered, 0 integrity failures).
- **B7 memory controls** — `pie memory inspect` (provenance) and `pie memory correct` (safe
  supersede: accept-new-then-forget-old).
- **Consolidated gate** — `pie verify-full` greens the entire battery in one command.
- Plus two real bugs fixed en route: `memory accept` passing an empty `-Project` to the policy
  engine, and the `inspect`/`correct` limit exceeding the memory reader's max.

## Why it was capped here

The line stopped at the boundary between *what could be built and verified in this environment* and
*what genuinely cannot be*:

1. **Everything sealed here is verifiable now.** Foundations + adoptions each have a green,
   fail-closed, fault-injected test reachable from `pie verify-full`. That is a coherent, provable
   unit — the right place to seal.
2. **The remaining Phase-1 items require capabilities this line could not exercise honestly.**
   - Author-side constraint: these scripts were written in an environment with **no PowerShell/
     Ollama/ONNX runtime**, verified only by the user running them on Windows. That worked because
     each change was small and testable. The deeper items are not.
   - **OS-level process-kill / power-loss injection** needs a harness that actually kills processes
     mid-write and cuts power — not the in-process simulated crash state we test today. That is real
     infrastructure, not a script edit.
   - **Multi-hour / multi-day soak with concurrent writers and a second repository** needs scheduling
     and wall-clock time; the harness exists (`pie soak`) but a genuine long run is its own effort.
   - **Real-model semantic drift evaluation (B5)** needs pulled models per tier and a scoring
     methodology — hashes prevent state substitution but cannot prove a probabilistic model still
     remembers facts.
   - **Compaction live-path unification + hosted gateway + desktop signing** each edit an
     integrity-sensitive or externally-gated surface that should not be changed blind.
3. **Evidence discipline.** Per PIE LAW, a claim is only valid with a verifiable artifact. Sealing
   here keeps every green claim backed by a passing gate, and defers the items whose proof cannot yet
   be produced — rather than half-adopting them without evidence.

## Deeper Phase-1 tranche (next line of development)

In recommended order:

1. **OS-level fault injection** — a harness that kills the `pie` process (and simulates power loss)
   at each multi-file transition point, asserting `pie recover` / load-time recovery restores
   consistency. Extends B2/B3 from simulated to real crashes.
2. **Genuine multi-hour soak** — schedule `pie soak` with large `-Sessions/-TurnsPerSession/-Cycles`,
   add concurrent writers and a second repository, and fold backup export/restore into the churn.
   Extends B4.
3. **Real-model drift evaluation (B5)** — per-tier fact-retention eval with a scoring harness and
   baseline receipts.
4. **Compaction live-path adoption** — unify `Get-CompactHistory` onto `PIE_CompactContext`, source
   pinned facts from memory, emit a per-turn compaction receipt; verify with the session suite.
5. **Phase 4/5** — desktop release gates (schema-migration coverage, updater rollback, Windows
   signing) and the hosted gateway (auth, tenant isolation, the persona-parity contract already
   specified).

Re-seal after each tranche by re-running the freeze once `pie verify-full` (extended with the new
checks) is green again.
