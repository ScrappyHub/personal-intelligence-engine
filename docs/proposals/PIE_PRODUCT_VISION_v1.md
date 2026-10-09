# PIE Product Vision Proposal v1 — "Have a piece of the PIE"

Status: **proposal, owner decisions recorded 2026-10-09**. Canonical files (`SPEC.md`,
`LAW.md`, `docs/canonical/*`, `project.contract.json`) are unchanged. §7 lists the canonical
edits this proposal would need. Per `docs/canonical/ECOSYSTEM_INTEGRATION.md` § Change governance,
adopting them also requires a Constellation registry update, integration tests, and a doctor receipt.

`../Constellation/` was not present beside this checkout, so the service map, registry, agent
policy, and shared invariants have not yet been read against this proposal.

Repository: https://github.com/ScrappyHub/personal-intelligence-engine

---

## 1. Vision

PIE (Personal Intelligence Engine) is two separate things under one name:

1. **PIE Hub** — this repository. It is a cross-platform desktop AI app, comparable to the Claude
   or ChatGPT desktop apps, for every kind of model: local and cloud. It provides:
   - model download, verification, and switching;
   - code governance, where users force a language or apply restrictions and safeguards;
   - integrations with Figma, Git, Supabase, Vercel, Cloudflare, and similar tools;
   - benchmarking with sealed evidence.
2. **The PIE model** — one strong, current, fully local model. **This is the largest piece of
   the project.** It is built completely separately from the Hub. The Hub treats it as one more
   model in its catalog.

Motto: *"Have a piece of the PIE."*

---

## 2. Owner decisions (2026-10-09)

| # | Question | Decision |
|---|---|---|
| D1 | Does PIE train models? | **The Hub never trains.** The "not a model training platform" non-goal stays true for the Hub. Exactly **one** PIE model is produced, in a separate repository or service. |
| D2 | Separation | The PIE model is **completely separate** from the Hub: separate repo, separate release cycle, separate data. The only interface is a sealed model release that the Hub installs like any other model. |
| D3 | Cloud API models | **Included** (Claude, OpenAI, Gemini, and others). Rules for keeping them optional under Law 1 are in §4. |
| D4 | Platforms | **Windows, macOS, Linux.** |

---

## 3. What already exists in the Hub

| Area | Existing in repo | Maturity |
|---|---|---|
| Model hub | `pie.ps1 models catalog / pull / use / validate`; 14-entry curated Ollama catalog; digest + bytes recorded per download | Working (Ollama only) |
| Model registry | `models/PIE_MODEL_REGISTRY.v1.json`, `schemas/model_manifest.v1.schema.json`, `pie_model_seal_v1.ps1` | Working |
| Other local backends | llama.cpp and ONNX adapters + selftests | Present; Ollama is the only first-class path |
| Language enforcement | `rules/languages/PIE_LANGUAGE_PROFILES.v1.json` | **Defined but not referenced by any code** |
| Safeguards | exec policy, capability graph/registry, propose → `-Yes` → receipt | Working for command execution only |
| Desktop | Electron shell over loopback workbench | Dev preview, `release_verified: false` |
| Integrations | Supabase, Figma, Vercel, Cloudflare: read-only auth verification | No Git provider; no actions |
| Benchmarks | `pie_benchmark_v1.ps1` + 2 keyword trials | No public suites |
| Evidence | Tier-0 packet pipeline FULL_GREEN, hash-chained sessions, HAAI capture | Strong |
| Cloud models | none (persona text only) | Not started |

---

## 4. Cloud API models under Law 1 (offline-first)

Law 1 says PIE must not *require* cloud services. Cloud models are allowed when all of the
following hold:

1. **Opt-in.** Every cloud provider is off by default. Enabling one is an explicit user
   action that is recorded in a receipt.
2. **Never required.** No GREEN gate, selftest, or core workflow depends on a cloud model. With
   networking disabled, the Hub works fully on local models. Cloud entries show `unavailable`
   and never fail silently (Integration rule 7).
3. **Disclosed in evidence.** Every run record and packet includes `backend_class:
   "local" | "cloud"`, provider, provider model ID, and `network: true` for cloud runs. A
   packet must never imply that a cloud run was local.
4. **Credentials stay in the OS keychain.** That means Windows Credential Manager, macOS
   Keychain, or Linux Secret Service. Credentials never appear in repo files, receipts, logs,
   or browser storage. This matches the current integrations rule.
5. **One adapter contract.** Cloud backends implement the same
   `schemas/pie.adapter.contract.v1.json` as local backends. A cloud backend can never be the
   implicit default.
6. **Context visibility.** When a session switches from a local model to a cloud model, the
   user is shown that conversation and project context will leave the machine.

Proposed canonical wording (for §7): *"PIE must function fully with networking disabled. Cloud
model backends are optional, disabled by default, and every cloud-backed run is disclosed as
such in its run record."*

---

## 5. Cross-platform (Windows / macOS / Linux)

Current state: ~22.7k lines of PowerShell under `scripts/` + `pie.ps1`, written for PowerShell 5.1.
`workbench/server.js` spawns `powershell.exe`. The Electron desktop shell is already
cross-platform. Windows-specific spots found so far:
- `powershell.exe` spawn in `workbench/server.js`;
- `%LOCALAPPDATA%` usage in `install.ps1`, `pie_doctor_v1.ps1`, `pie_runtime_v1.ps1`, and
  `pie_ollama_ensure_v1.ps1`;
- backslash paths in about 17 scripts;
- Ollama install and process control.

**Recommended path: standardize the engine on PowerShell 7 (`pwsh`).** PowerShell 7 runs
natively on all three operating systems.
- Ship or require `pwsh` 7.4 LTS. Replace `powershell.exe` spawns with a resolved `pwsh` path.
- Replace hard-coded `\` paths with `Join-Path` / `[IO.Path]`, and replace `%LOCALAPPDATA%`
  with per-OS app-data roots:
  - Windows: `%LOCALAPPDATA%\PIE`
  - macOS: `~/Library/Application Support/PIE`
  - Linux: `$XDG_DATA_HOME/pie`
- Keep the canonical-bytes rules (UTF-8 no BOM, LF) unchanged on every OS. The Tier-0 golden
  vectors must produce **identical packet IDs** on all three operating systems. That is the
  cross-platform acceptance test.
- CI matrix: `windows-latest`, `macos-latest`, `ubuntu-latest`, running the full GREEN suite.

Alternative: rewrite the engine in a compiled language such as Rust or Go. This is not
recommended now. It would discard about 22k lines of tested, sealed behavior before the
product exists.

---

## 6. The PIE model (separate repository — the largest piece)

PIE Hub has no dependency on this track beyond consuming its sealed release.

**Realistic approach:** do not pre-train from scratch. Building a frontier-class model from
scratch needs thousands of GPUs and trillions of tokens. The achievable path to "one good,
up-to-date AI" is to **post-train a current open-weight base model**:

1. **Pick a base.** Choose a current open-weight model whose license permits derivatives and
   that is sized for consumer hardware (for example ~7–32B dense, or a small mixture-of-experts
   model). Pin the exact weights by SHA-256.
2. **Supervised fine-tuning.** Use curated, licensed instruction data, emphasizing coding,
   tool use, and PIE's governance behaviors (language forcing, refusal outside granted scope).
3. **Preference tuning** (DPO/ORPO or similar) for helpfulness and instruction following.
4. **Quantize** to GGUF tiers (for example Q4_K_M / Q5_K_M / Q8_0) so it runs on laptops.
5. **Evaluate** with the Hub's benchmark harness (§8, Phase 4). Release only with sealed
   benchmark packets that compare the PIE model against its own base.
6. **Release** as a sealed model manifest: weights hashes, license, base lineage, dataset
   manifest hashes, and eval packet IDs. The Hub installs it through its normal catalog.

"Only works when it's supposed to" is enforced in **two layers**:
- the model is trained to stay in scope;
- the Hub's runtime enforces scope with capability policy, intent profiles, and exec policy,
  so behavior does not depend on the weights alone.

Data rule: PIE Hub session data is never used for training unless the user explicitly opts in
per export. Opted-in data travels as a sealed packet.

Suggested repo name: `pie-model` (or `pie-forge`), registered in Constellation as a producer
upstream of `pie`.

---

## 7. Canonical changes this proposal would require (not yet made)

1. `SPEC.md` Mission/Invariant 1: replace "personal, offline" with the §4 wording that
   keeps offline as the guarantee and allows optional cloud backends.
2. `SPEC.md` Non-goals: keep "Not a model training platform". Add "Model production lives in the
   separate PIE model repository".
3. `SPEC.md` Components: add cloud backend adapters and the cross-platform runtime (`pwsh` 7).
4. `LAW.md` Law 1: same clarification as item 1.
5. `docs/canonical/ECOSYSTEM_INTEGRATION.md`: fill in ownership (§9). Upstream services:
   `pie-model` (sealed model releases). External optional providers: cloud model APIs, plus
   Figma, Git, Supabase, Vercel, Cloudflare.
6. `project.contract.json`: matching `upstream_services` and role text.
7. Constellation `registry/services.json` + service map re-publish.

---

## 8. Hub roadmap

Each phase ends with a GREEN gate and receipts.

**Phase 0 — Cross-platform foundation (§5).** Migrate to `pwsh` 7, fix paths and app-data
roots, and set up the 3-OS CI matrix. Gate: identical golden packet IDs on all three operating systems.

**Phase 1 — Hub & desktop parity**
- First-class llama.cpp/GGUF backend; Hugging Face GGUF import with SHA-256 pinning.
- Cloud adapters (Anthropic, OpenAI, Google; OpenAI-compatible generic endpoint) under §4.
- Model cards: size, license, context length, hardware fit, local vs cloud badge.
- Desktop UX parity: conversation list, projects, attachments, streaming, model switcher,
  settings. Signed installers for all three operating systems.

**Phase 2 — Code governance**
- Wire `PIE_LANGUAGE_PROFILES` into context building and a post-generation check.
  *Force language* rejects or regenerates output whose code is not in the chosen language.
- Per-project restriction sets: banned APIs/imports, required patterns, license headers.
  These are checked by parse gates and linters, each producing a `pie.policy.decision.v1`
  receipt.
- Selectable safeguard profiles (strict / standard / permissive) that apply equally to local
  and cloud models.

**Phase 3 — Integrations with actions**
- Add a Git provider (local git first, GitHub optional).
- Figma, Supabase, Vercel, and Cloudflare get read actions first. Write actions are proposal-only:
  `-Yes` plus a receipt.
- Expose integrations through MCP so every model in the Hub uses them uniformly.

**Phase 4 — Benchmarks as evidence**
- Run public suites locally with pinned dataset hashes (for example HumanEval+/MBPP+,
  LiveCodeBench, MMLU-Pro, GSM8K, IFEval).
- Every run is a sealed packet containing model digest, prompt template, sampling params,
  harness version, and scores. Under LAW.md, a score with no packet is not a valid claim.
- Leaderboard on the user's own hardware, covering local and cloud models side by side.
  This is also the evaluation harness for the PIE model.

---

## 9. Proposed ownership

PIE Hub owns:
- model catalog, download, verification, and selection (local + cloud);
- inference adapters;
- governed sessions, memory, and code-governance policy;
- the cross-platform desktop/workbench;
- sealed run and benchmark packets.

PIE Hub does not own:
- model training (owned by `pie-model`);
- hosted multi-tenant services;
- third-party service state, which is accessed only through receipted integrations.

---

## 10. Remaining open questions

1. Licensing for the Hub and for the PIE model ("License to be determined").
2. PIE model base and size target, which drives the hardware floor for users.
3. Approval of the `pwsh` 7 path (§5) versus a rewrite.

## 11. Survey findings to fix

- `models/PIE_MODEL_REGISTRY.v1.json` and `rules/languages/PIE_LANGUAGE_PROFILES.v1.json` start
  with a UTF-8 BOM. If either is hashed or signed, this violates Law 2.
