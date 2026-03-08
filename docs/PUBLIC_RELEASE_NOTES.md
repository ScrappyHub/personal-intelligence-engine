# PIE Public Release Notes

## Release: Tier-0 First FULL_GREEN Standalone Freeze

PIE has reached its first public **Tier-0 FULL_GREEN standalone state**.

### Meaning of this release

This release proves that PIE can operate as a standalone offline-first instrument without requiring ecosystem integrations for correctness.

The canonical standalone packet pipeline is now proven end-to-end:

1. materialize deterministic vectors
2. seal a deterministic run
3. build a Packet Constitution v1 Option A packet
4. sign the packet
5. independently verify the packet
6. pass positive vectors
7. reject negative vectors deterministically

### Authoritative green tokens

```text
SELFTEST_PIE_TIER0_V1_GREEN
PIE_TIER0_FULL_GREEN_V1_OK
Authoritative scripts
scripts\_RUN_pie_tier0_full_green_v1.ps1
scripts\_selftest_pie_tier0_v1.ps1
scripts\pie_materialize_vectors_v1.ps1
scripts\pie_seal_run_v1.ps1
scripts\pie_build_packet_optionA_v1.ps1
scripts\pie_run_packet_sign_v1.ps1
scripts\pie_verify_packet_optionA_v1.ps1
scripts\_lib_pie_tier0_v1.ps1
Evidence captured
freeze\PIE_TIER0_FREEZE_MANIFEST_v1.txt
proofs\runs\pie0\
test_vectors\
docs\wbs\PIE_WBS_PROGRESS_LEDGER_v1.md
Scope of this release

This release establishes:

standalone packet correctness

deterministic vector materialization

independent verification behavior

first public freeze state

This release does not yet represent final public polish for:

repo surface cleanup

archival separation of historical repair scripts

final licensing decision

final offline runtime product messaging

final schemas package

Project posture

PIE is standalone first.

Ecosystem integrations remain deferred until the standalone instrument is fully documented, cleaned, and stabilized.