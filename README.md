# Personal Intelligence Engine (PIE)

PIE is a Tier-0 standalone offline-first personal AI engine runtime.

Its proven Tier-0 surface is a deterministic packet pipeline:

- materialize vectors
- seal a run
- build a Packet Constitution v1 Option A packet
- sign the packet
- independently verify the packet
- pass positive vectors
- fail negative vectors deterministically

## Tier-0 status

Current proven standalone GREEN tokens:

- `SELFTEST_PIE_TIER0_V1_GREEN`
- `PIE_TIER0_FULL_GREEN_V1_OK`

## Canonical rules

- standalone first; ecosystem integration is deferred
- Packet Constitution v1 Option A
- manifest without `packet_id`
- `packet_id.txt` derived from canonical manifest bytes
- `sha256sums.txt` generated last
- verifier is non-mutating
- UTF-8 no BOM + LF
- Windows PowerShell 5.1 + StrictMode

## Authoritative scripts

- `scripts\_RUN_pie_tier0_full_green_v1.ps1`
- `scripts\_selftest_pie_tier0_v1.ps1`
- `scripts\pie_build_packet_optionA_v1.ps1`
- `scripts\pie_verify_packet_optionA_v1.ps1`
- `scripts\pie_run_packet_sign_v1.ps1`
- `scripts\pie_materialize_vectors_v1.ps1`

## Next lock steps

- freeze/clean negative vector label semantics
- emit deterministic receipts/transcripts/sha256 evidence bundle
- publish stronger README/release notes for the proven standalone surface
