# PIE Engine — Backend Adapters

Per `SPEC.md`, backend adapters live under `engine/`. An adapter turns a sealed model
identity plus a prompt into deterministic run output that the recording law
(`scripts/pie_run_v1.ps1` + `scripts/_lib_pie_v1.ps1`) can hash, ledger, and later seal into a
Packet Constitution v1 Option A packet.

## Design rules

1. **Recording law is invariant.** An adapter only produces `output` bytes. Input hashing,
   params hashing, output hashing, the append-only hash-linked run ledger, and plaintext
   input/output artifacts are always produced by `pie_run_v1.ps1`, never by the adapter.
2. **Sealed-model binding stays.** A run still requires a sealed model manifest under
   `registry/models/<model_id>/model_manifest.v1.json` (`sums_sha256`, `weights_sha256`). The
   adapter does not relax content addressing.
3. **Offline-first.** The default backend remains `stub` — fully deterministic and
   network-free — so the frozen Tier-0 pipeline behavior is unchanged. Real backends are
   opt-in via `pie_run_v1.ps1 -Backend <name>`.
4. **Fail-closed with clear tokens.** Adapter failures raise `PIE_ENGINE_*` error tokens; they
   never silently fall back to the stub.

## Adapters

| Name | Contract | Status | Notes |
|---|---|---|---|
| `stub` | (built in) | ready | Deterministic placeholder output; default; used by frozen Tier-0 vectors |
| `ollama` | `engine/adapters/ollama/PIE_ENGINE_ADAPTER.v1.json` | preview | Real local generation via the loopback Ollama host; opt-in |
| `llamacpp` | `engine/adapters/llamacpp/PIE_ENGINE_ADAPTER.v1.json` | scaffold | Real local generation via a loopback llama.cpp server (`/completion`, `temperature 0`); opt-in; not yet executed against a live server |
| `onnx` | `engine/adapters/onnx/PIE_ENGINE_ADAPTER.v1.json` | scaffold | Native Windows, fully-offline generation via onnxruntime-genai; **subprocess** shape (Python helper), not HTTP; opt-in; not yet executed against a real ONNX model |

Planned (per `SPEC.md`, not yet implemented): `vLLM` (safetensors) — deferred as an advanced/optional GPU-server backend that clashes with offline-first-Windows as a default.

Integration shapes: `ollama`, `llamacpp`, and `vLLM` are **HTTP** (loopback server). `onnx` is
**subprocess** — `pie_run_v1 -Backend onnx` → `pie_backend_onnx_cmd_v1.ps1` (resolves the sealed
model dir) → `pie_backend_onnx_generate_v1.py` (onnxruntime-genai).

Backend status ladder: `scaffold` (authored, unexecuted) → `preview` (runs, not soak-tested) →
`ready` (verified with positive + negative tests and durable receipts).

## Shared persona (alignment across backends and surfaces)

Every backend uses one persona/system prompt: `engine/PIE_PERSONA.v1.txt` (loaded via
`scripts/_lib_pie_persona_v1.ps1`, with a fail-safe embedded fallback). This guarantees the model
behaves the same regardless of backend (ollama/llama.cpp/onnx) and regardless of surface
(self-hosted-local vs a hosted API gateway). The persona encodes three non-negotiables:

1. **Identity honesty** — PIE is the runtime/memory/verification layer; the LM is local; never
   impersonate a hosted assistant.
2. **Minimalism** — do only what the user asked; never add features/files/scope the user did not
   request; offer extras, don't impose them.
3. **Local/hosted parity** — hosting must not change identity, honesty, or scope discipline.

Any hosted gateway MUST load the same `PIE_PERSONA.v1.txt` so web and local stay aligned.

## Determinism note

A real language-model backend is not bit-reproducible across hosts. When a run is sealed with a
non-`stub` backend, the packet proves *what was produced and by which sealed model set on this
host at this time* — it does not claim cross-host replay. Cross-host deterministic replay is
only claimed for the `stub` backend and for pinned-vector pipelines. See
`docs/proposals/PIE_STATE_INTEGRITY_HARDENING.md` (real-model drift evaluation remains a release
blocker).
