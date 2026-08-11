# PIE Desktop And Hosted Architecture Proposal

Status: implementation proposal. This does not redefine PIE's canonical standalone-first role.

## Product surfaces

PIE should ship one workbench UI through two capability-aware shells:

- **PIE Desktop** packages the verified PIE runtime, starts it on loopback, opens local repositories through an explicit native folder picker, hosts local models through Ollama, and stores recent project paths on the user's machine.
- **PIE Hosted** serves the compact web workbench without local filesystem or process access. Repositories must arrive through an authenticated provider connection or an explicit archive upload into an isolated workspace.

The visual system, conversation flow, model metadata, memory concepts, and portable run receipts remain shared.

## Trust boundaries

Desktop renderer code receives only narrowly typed repository-picker methods through an isolated preload bridge. Node integration stays disabled, renderer sandboxing remains enabled, navigation is loopback-only, and the existing per-process workbench token protects API calls.

Hosted deployments must not expose `pie.ps1`, Ollama, arbitrary host paths, or the desktop preload bridge. A hosted gateway must authenticate every user, validate archive limits and paths, create one isolated workspace per import, and route model calls through an explicitly configured hosted backend.

## Scaling path

1. Harden the local browser workbench and packaged desktop state model under adversarial restart, corruption, isolation, and drift tests.
2. Add signed release artifacts, verified automatic update metadata, and rollback only after the state gates pass.
3. Add a hosted gateway contract for authentication, repository imports, storage, jobs, quotas, and receipts.
4. Deploy the static workbench separately from the gateway so either tier can scale independently.

## Release gates

- Desktop installer contents are reproducible and checksummed.
- Mutable desktop state is stored outside replaceable application bytes and migrates with verified receipts.
- Session repository identity, model digest, goal, backend, and conversation chain fail closed on drift.
- Project memory is bound to an exact repository identity; disabled memory injects no source.
- Crash, concurrent-write, restart, upgrade, rollback, backup, restore, and corruption tests pass.
- Repeated real-model evaluations measure semantic goal, project, and factual continuity across long chats.
- Windows code signing is configured before public production distribution.
- No renderer API accepts arbitrary IPC channels or shell commands.
- Hosted repository extraction rejects traversal, links, excessive file counts, and expanded-size attacks.
- Hosted credentials and user repository contents never enter local release artifacts.

Passing a packaging smoke test does not satisfy these release gates.
