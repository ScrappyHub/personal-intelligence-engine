# Personal Intelligence Engine (PIE)

PIE is an offline-first personal AI runtime that treats AI execution as a verifiable instrument, not a cloud service.

## Core guarantees (canonical)
- Offline capable (no network required)
- Model weights are content-addressed (SHA-256) and recorded per run
- Canonical JSON bytes for all signed / hashed records
- Deterministic receipts + append-only local run ledger
- Optional signing via ssh-keygen -Y with NeverLost v1 trust
- Optional NFL duplication (Canonical Handoff v1) and WatchTower verification

## Layout
- models/ : local weight storage (GGUF, safetensors, etc.)
- registry/ : model manifests and index
- runs/ : run records + transcripts (hash-linked)
- proofs/ : NeverLost v1 identity + trust + receipts
- packets/ : Echo Transport outbox/inbox/receipts (Packet Constitution v1 compatible)
- scripts/ : deterministic tooling (PS5.1-safe)

## Quick start
1) Initialize NeverLost trust bundle: proofs/trust/trust_bundle.json
2) Generate allowed_signers: scripts\make_allowed_signers_v1.ps1
3) Register a model (hash + manifest): scripts\pie_register_model_v1.ps1
4) Run PIE (records run + hashes): scripts\pie_run_v1.ps1

## Status
- This repo locks determinism + governance scaffolding. Backend inference adapters (llama.cpp/vLLM/etc.) plug into engine/.
