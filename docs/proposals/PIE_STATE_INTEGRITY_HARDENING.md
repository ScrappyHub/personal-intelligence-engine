# PIE State Integrity Hardening

Status: implementation and release-gate proposal. This does not redefine PIE's unclassified canonical ecosystem role.

## Problem

Desktop readiness requires more than a window and an installer. PIE must prevent one conversation, repository, model, or memory scope from silently becoming another across requests, restarts, upgrades, concurrent processes, and partial failures.

## Implemented In This Pass

- New sessions bind repository path and identity, backend, model identity, goal, and conversation format into verified state.
- Ollama sessions pin the locally reported model digest; a changed tag fails before inference.
- Conversation turns use an indexed SHA-256 chain and are parsed fail-closed.
- Concurrent chat and memory writers are rejected with exclusive locks.
- Reusing a session name with another binding fails without mutating the original session.
- Legacy sessions remain readable but cannot execute, resume, or receive new turns.
- Project memory requires an exact repository path and identity. Same-named folders do not share memory.
- Active memory is excluded from project sessions. Memory mode `off` excludes personal and repository memory.
- The workbench restores its visible transcript from the same verified history used by the backend.
- The workbench indexes verified, legacy, busy, and corrupt sessions instead of silently hiding damaged history.
- Session readers and writers share one operation lock, including transition recovery and session indexing.
- Integrity-bearing session text is decoded as strict UTF-8 across Windows PowerShell 5 and PowerShell 7.
- Packaged desktop state lives in a stable user workspace. Application bytes synchronize from a verified manifest while `runs`, `memory`, and `.pie` remain mutable.
- First migration from an older bundled runtime emits a per-file SHA-256 receipt.
- Interactive chat now creates the immutable project, goal, backend, and model binding before any session state, and resumes only a verified matching session.
- Visible conversation history stores the exact user message while attachment-expanded model context remains a separate input artifact.
- Repository context uses canonical identity/current-state/spec excerpts and applies PIE-specific capability labels only to PIE itself.
- HAAI export is explicit and idempotent, uses HAAI's capture/build/verify commands, independently verifies packet hashes, and writes only inside the bound PIE session.
- HAAI-bound project tests prove project-memory isolation, canonical identity grounding, governed execution receipts, and no writes to HAAI canonical or source files.
- `pie doctor` emits a versioned component report and always keeps development availability separate from release readiness.
- The hosted UI hides local runtime installation, host model downloads, host paths, and local-only connection controls; the production hosted gateway remains unimplemented.
- Session backup v1 exports complete verified sessions under an exclusive lock with a SHA-256 file manifest and deterministic payload identity.
- Backup verification rejects corruption, duplicate entries, unmanifested files, traversal, oversized payloads, and malformed UTF-8 metadata before restore.
- Restore is collision-safe, re-runs PIE's binding and conversation verifier, and removes a newly restored directory if post-restore verification fails.
- The local workbench can create idempotent backups; archive selection for restore is limited to the sandboxed desktop file picker and is absent from the hosted gateway.
- Backup payloads are encrypted in full with AES-256-GCM and scrypt-derived keys; only authenticated cryptographic parameters remain outside the ciphertext.
- Every export uses a fresh 32-byte salt and 12-byte nonce with a full 16-byte authentication tag. Wrong passphrases, header changes, and ciphertext changes fail before ZIP verification.
- Passphrases use secure prompts or process stdin and are cleared from UI fields; they are never placed in process arguments, receipts, logs, browser storage, or persistent session state.

## Release Blockers

- Define and test versioned migrations for every persistent schema, not only the initial desktop workspace relocation.
- Extend encrypted backup v2 with explicit cross-machine repository-path/model migration and a reviewed key-recovery design; silent rebinding remains forbidden.
- Add process-kill and power-loss fault injection around every multi-file state transition.
- Add disk-full, permission-loss, antivirus-lock, and interrupted-update tests.
- Add multi-hour and multi-day restart/soak tests across multiple repositories and sessions.
- Build real-model drift evaluations across every supported model tier. Hashes prevent state substitution; they cannot guarantee that a probabilistic model remembers or follows facts.
- Add explicit user controls for memory inspection, provenance, acceptance, correction, forgetting, and project scope.
- Define deterministic conversation compaction or pinned-fact behavior when a chat exceeds the active model context window.
- Verify update rollback preserves and reopens the same state without downgrade ambiguity.
- Complete accessibility, installer/uninstaller, Windows signing, SmartScreen reputation, and supported-OS testing.
- Complete hosted authentication, tenant isolation, repository import, secret handling, quotas, deletion, and audit evidence before hosting user data.

## Current Verification Checkpoint

On 2026-08-10, the full runtime suite passed after targeted regressions covered concurrent workbench indexing, cross-shell non-ASCII conversation verification, shared redirected-process handles, transaction recovery, memory isolation, exact chat reopen, authenticated encrypted session backup/restore, model and repository identity replacement, HAAI evidence export and project isolation, hosted capability boundaries, packaging, installation, and desktop workspace migration.

This checkpoint is development evidence only. It does not include a real-model semantic drift soak, signed installer validation, cross-machine backup migration, recovery-key design, update rollback, accessibility review, or a completed visual browser pass.

## Evidence Rule

PIE must not call a desktop or hosted artifact release-ready until every applicable blocker has a repeatable positive test, negative test, and durable receipt. A successful package, launch, or single model response is insufficient.
