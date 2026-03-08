# Personal Intelligence Engine (PIE)

PIE is a Tier-0 standalone, offline-first personal AI engine runtime.

## What this project is to spec

- PIE is a standalone personal AI runtime that must stand on its own before any ecosystem integration.
- Its Tier-0 correctness does not depend on NFL, WatchTower, or other Covenant ecosystem services.
- It produces deterministic run export packets through a sealed pipeline:
  - seal
  - build
  - sign
  - verify
  - receipts
- Transport law is Packet Constitution v1 Option A:
  - `manifest.json` does not contain `packet_id`
  - `packet_id.txt` is derived from canonical manifest bytes
  - `sha256sums.txt` is generated last
  - verification is non-mutating

## Current canonical state

PIE Tier-0 standalone packet pipeline is FULL_GREEN.

Proven green tokens:

- `SELFTEST_PIE_TIER0_V1_GREEN`
- `PIE_TIER0_FULL_GREEN_V1_OK`

This means the current authoritative Tier-0 pipeline can:

- materialize vectors
- seal a deterministic run
- build a valid Option A packet
- sign the packet
- verify the valid packet independently
- verify positive vectors
- reject negative vectors with expected failure behavior

## Authoritative scripts

- `scripts\_RUN_pie_tier0_full_green_v1.ps1`
- `scripts\_selftest_pie_tier0_v1.ps1`
- `scripts\pie_build_packet_optionA_v1.ps1`
- `scripts\pie_verify_packet_optionA_v1.ps1`
- `scripts\pie_run_packet_sign_v1.ps1`
- `scripts\pie_materialize_vectors_v1.ps1`

## Key supporting artifacts

- `docs\wbs\PIE_WBS_PROGRESS_LEDGER_v1.md`
- `docs\PACKET_SPEC_PIE.md`
- `docs\SPEC_RUN_MODEL.md`
- `freeze\PIE_TIER0_FREEZE_MANIFEST_v1.txt`
- `test_vectors\`
- `proofs\runs\pie0\`

## Repository status

PIE is being hardened as a public standalone product first.

Ecosystem integrations are explicitly deferred until the standalone surface is proven, documented, and stable.

## Next locked work

- clean public repo surface
- reduce scratch/backups from primary public narrative
- add stronger README/spec docs for outsiders
- harden receipts/transcripts/evidence bundle
- clarify offline runtime and impact metrics
- prepare a cleaner public-facing release pack