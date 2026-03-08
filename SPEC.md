# PIE SPEC v1

## Mission
Provide a personal, offline, verifiable AI runtime so individuals and small orgs can use AI without mandatory reliance on hyperscale cloud infrastructure.

## Non-goals
- Not a model training platform (inference-first)
- Not a centralized SaaS
- No hidden telemetry

## Canonical invariants
1) Offline-first: PIE must function with networking disabled.
2) Content addressing: model weights and run artifacts are identified by SHA-256 of canonical bytes.
3) Canonical JSON bytes: all signed/hashed JSON is serialized with sorted keys, no whitespace, stable escaping, UTF-8 no BOM, LF.
4) Append-only run ledger: runs are recorded as append-only NDJSON with hash-linking (prev_hash).
5) NeverLost v1 identity: optional signing/verify uses trust_bundle.json -> derived allowed_signers.
6) Namespace enforcement: signatures must be verified for the namespace declared by the repo (default: pie).
7) No silent drift: any mutation must be detectable (hash mismatch, chain break, signature failure, missing receipt).

## Components
### Model Registry
- registry/models/<model_id>/model_manifest.v1.json
- Contains: model_id, weights paths, sha256, backend adapter, license metadata.

### Runtime Engine
- Backend adapters live under engine/.
- Initial adapters expected: llama.cpp (GGUF), vLLM (safetensors), ONNX (optional).

### Run Recording
- Each run emits run_record.v1.json + optional transcript.
- Local pledge log: runs/run_ledger.ndjson (append-only).

### Optional Witness + Verification
- NFL duplication via Canonical Handoff v1 (outbox/inbox when offline).
- WatchTower verifies hashes/signatures and emits receipts.
