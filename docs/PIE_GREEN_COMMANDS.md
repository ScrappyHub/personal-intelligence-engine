# PIE Green Commands

PIE has multiple green lanes. They are intentionally separate so routine governance work does not require a full monolithic proof run every time.

## Command surface

    pie green status
    pie green list
    pie green evidence
    pie green manifest
    pie green governance
    pie green governance-full
    pie green full

## pie green status

No tests are executed.

Prints the current evidence state:

- current branch
- current commit
- working tree clean or dirty state
- latest canonical full-green freeze
- latest governance-green freeze
- governance freeze mode
- governance freeze status
- governance selftest count

## pie green list

No tests are executed.

Reads docs/PIE_GREEN_COMMANDS.manifest.json and prints every registered green command with its purpose.

## pie green evidence

No tests are executed.

Reads the latest full-green freeze and latest governance-green freeze, then prints:

- freeze directory
- summary path
- summary schema
- status
- mode when present
- selftest count
- created timestamp when present
- sha256sums.txt path
- sha256 hash of sha256sums.txt
- child receipt count

## pie green manifest

No tests are executed.

Validates the machine-readable green command manifest against the implemented and documented green command surface.

It checks:

- manifest schema
- command root
- command count
- expected commands
- expected modes
- CLI routes in pie.ps1
- docs command coverage
- governance runner contract tokens
- evidence filename expectations
- lifecycle coverage declaration
- green-lane governance rules

## pie green governance

Fast latest-governance lane.

This is the normal lane for current trusted-baseline governance work. It runs the currently relevant governance checks without rerunning the entire historic full-green stack.

Current scope:

- cross-repo negative regression drift vector
- trusted baseline enforcement
- readable baseline governance report

Evidence shape:

    proofs/freeze/pie_governance_green_<timestamp>/
      FREEZE_SUMMARY.json
      child_receipts.ndjson
      parse_gate_sha256s.txt
      sha256sums.txt
      cross_repo_regression_negative_stdout.txt
      cross_repo_regression_negative_stderr.txt
      cross_repo_baseline_enforce_stdout.txt
      cross_repo_baseline_enforce_stderr.txt
      cross_repo_baseline_governance_report_stdout.txt
      cross_repo_baseline_governance_report_stderr.txt

## pie green governance-full

Fast trusted-baseline lifecycle lane.

This lane proves the trusted-baseline lifecycle without chaining older stateful baseline selftests that reuse fixed baseline IDs in shared memory.

Current scope:

- cross-repo negative regression drift vector
- readable baseline governance report selftest

The readable report selftest proves the full trusted-baseline lifecycle internally:

    promote
    revoke
    replace / supersede
    lineage audit
    readable governance report

## pie green full

Canonical full-green delegate.

This delegates to:

    scripts/FULL_GREEN_RUNNER_PIE_TIER0_v1.ps1

It produces the canonical full evidence freeze:

    proofs/freeze/pie_tier0_green_<timestamp>/

## Rule of thumb

Use the smallest green lane that proves the change.

| Change type | Recommended command |
|---|---|
| Check evidence state only | pie green status |
| Discover green commands | pie green list |
| Inspect latest green evidence | pie green evidence |
| Validate green command contract | pie green manifest |
| Trusted-baseline report or enforcement tweak | pie green governance |
| Trusted-baseline lifecycle semantics | pie green governance-full |
| Broad runtime, packet, execution, or release proof | pie green full |

## Evidence rule

Do not commit failed partial freezes.

If a green command fails:

1. inspect the stdout/stderr files in the generated freeze directory
2. fix forward
3. remove failed partial freeze evidence from git if accidentally staged
4. rerun the green lane
5. commit only the green runner/code and the latest successful freeze
