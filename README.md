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

# Run a model locally

PIE uses Ollama as its first local model host. Model files and inference stay on the user's machine.

```powershell
.\pie.ps1 runtime install
.\pie.ps1 runtime start
.\pie.ps1 models catalog
.\pie.ps1 pull -Model qwen2.5-coder:7b -SetDefault
.\pie.ps1 chat
```

Use `.\pie.ps1 models` to see downloaded models, `.\pie.ps1 models use -Model <name>` to switch the default, and `.\pie.ps1 runtime status` to inspect the local host. Once a model is downloaded, chat and inference can run without internet access.

Run `.\pie.ps1 doctor` for one read-only health audit of the CLI, memory, model catalog, runtime, conversations, workbench, desktop source, hosted contract, optional integrations, and HAAI adapter. The report is saved under `runs\doctor`; it always reports release readiness separately from development availability.

Back up a verified conversation with `.\pie.ps1 session export -SessionId <id>`. Validate an encrypted archive with `.\pie.ps1 session verify -Path <backup.piebak>` and restore it with `.\pie.ps1 session restore -Path <backup.piebak>`. Restore never overwrites an existing session, and version 1 intentionally requires the same repository path and identity.

The complete ZIP payload, including its manifest, filenames, prompts, attachments, execution output, and HAAI evidence, is encrypted inside the `.piebak` envelope with AES-256-GCM. PIE derives the key with scrypt using a fresh 32-byte salt and encrypts with a fresh 12-byte nonce and full 16-byte authentication tag. Passphrases are entered interactively or transferred to the local worker over stdin; they are not command arguments, receipts, logs, browser storage, or session state. Losing the passphrase makes the backup unrecoverable.

The curated catalog includes lightweight, everyday, coding, reasoning, vision, performance, and workstation choices. Run `.\pie.ps1 models catalog` to compare local storage tiers or `.\pie.ps1 models validate` to verify the catalog. PIE records the local Ollama digest and byte count after every successful download. Catalog metadata is sourced from the official Ollama library pages for [Qwen 3](https://ollama.com/library/qwen3), [Qwen 2.5 Coder](https://ollama.com/library/qwen2.5-coder), [Llama 3.2](https://ollama.com/library/llama3.2), [Phi-4 Mini](https://ollama.com/library/phi4-mini), [Gemma 3](https://ollama.com/library/gemma3), and [DeepSeek R1](https://ollama.com/library/deepseek-r1).

## Open the local workbench

PIE includes a browser workbench for choosing downloaded models, starting project sessions, chatting with the local agent, and checking optional connections. It listens only on this machine and routes requests through the same governed `pie.ps1` commands as the CLI.

```powershell
.\pie.ps1 workbench
```

Then open `http://127.0.0.1:4317`. Use `-Port <number>` to choose a different local port. Press Ctrl+C in the terminal to stop the workbench.

Model downloads show Ollama's real byte progress, survive a page reload, and are verified against the local model registry before PIE selects them.

The workbench includes persistent Sunset, Dusk, and system theme modes. On supported browsers it can also be installed as a compact PWA from the Install action in the title bar.

## Build PIE Desktop

PIE Desktop is a development preview, not a release-ready application. It wraps the loopback-only workbench in a sandboxed Electron window and keeps mutable sessions, memory, receipts, and configuration in a stable per-user workspace outside the replaceable application bundle.

```powershell
cd .\desktop
npm install
npm run package
```

The packaged development application is emitted under `desktop\release\PIE-win32-x64`. `npm run release` can produce an internal unsigned installer for verification work, but that artifact is not approved for distribution.

Public release remains blocked on state migration coverage, cross-machine backup migration and key-management recovery design, crash and power-loss fault injection, long-running real-model drift evaluations, updater rollback, Windows signing, and broader desktop workflow testing. See [the state-integrity hardening proposal](docs/proposals/PIE_STATE_INTEGRITY_HARDENING.md).

## Build the hosted workbench

The hosted artifact is a smaller static PWA configured for an HTTPS gateway. It intentionally excludes desktop IPC, host filesystem paths, Ollama process control, and the local per-process request token.

```powershell
.\scripts\pie_hosted_build_v1.ps1 -RepoRoot . -ApiBase "https://api.example.com"
```

The output under `dist\hosted` includes static assets, PWA metadata, Cloudflare Pages headers, and Vercel routing. The gateway must implement [the hosted contract](workbench/contracts/PIE_HOSTED_GATEWAY.v1.json) with authenticated, isolated repository imports before public deployment.

## Package and install PIE

Build a versioned PIE archive with a per-file manifest and SHA-256 sidecar:

```powershell
.\pie.ps1 package -Version 0.1.0
```

Install the package atomically for the current Windows user:

```powershell
.\install.ps1 -PackagePath .\dist\pie-0.1.0.zip -AddToUserPath
```

Remote installs require an HTTPS package URL and its expected SHA-256 value. The installer verifies the archive and every packaged file before changing the active PIE version, keeps versioned installations under `%LOCALAPPDATA%\PIE`, and writes an installation receipt locally.

## Run a governed local agent

Bind an agent session to a repository, inspect it with read-only capabilities, and preserve plans, snapshots, output, and execution receipts locally.

```powershell
.\pie.ps1 agent start -SessionId my_work -TargetRepo . -Goal "Inspect repository health"
.\pie.ps1 agent inspect -SessionId my_work
.\pie.ps1 agent ask -SessionId my_work -Text "Summarize the current state"
.\pie.ps1 agent status -SessionId my_work
.\pie.ps1 agent stop -SessionId my_work
```

A session name is permanently bound to its repository identity, model digest, backend, goal, and SHA-256 conversation chain. Reusing it with different bindings fails closed. Sessions created before this integrity contract remain readable through `agent status` and `agent history`, but are intentionally read-only; use a new session name to continue safely.

Verified turns can be preserved explicitly through HAAI with `.\pie.ps1 haai capture -SessionId <id>`. PIE invokes HAAI's own capture, build, and verify flow, independently rechecks the packet hashes, and stores the resulting evidence under that PIE session. No conversation is exported implicitly.

While a local model is working, PIE reports elapsed time every five seconds. Agent requests time out after 180 seconds and retry once by default. Override this per request with `-TimeoutSeconds`, `-Retries` (0-2), and `-ProgressIntervalSeconds`.

## Connect external services

PIE can inspect local CLI availability and verify read-only API authentication without printing or storing token values.

```powershell
.\pie.ps1 integrations status
.\pie.ps1 integrations verify -Provider supabase
.\pie.ps1 integrations verify -Provider figma
.\pie.ps1 integrations verify -Provider vercel
.\pie.ps1 integrations verify -Provider cloudflare
```

Credentials are read from `SUPABASE_ACCESS_TOKEN`, `FIGMA_ACCESS_TOKEN`, `VERCEL_TOKEN`, and `CLOUDFLARE_API_TOKEN`. Optional project context uses `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `VERCEL_TEAM_ID`, `CLOUDFLARE_ACCOUNT_ID`, and `CLOUDFLARE_ZONE_ID`. Keep secrets outside the repository.

Single read-only commands may auto-run when policy permits. Unknown or mutating commands produce proposals and require `-Yes`; destructive patterns remain denied even when confirmation is supplied.

---

# License

License to be determined.

The project is currently focused on stabilizing the standalone runtime.
