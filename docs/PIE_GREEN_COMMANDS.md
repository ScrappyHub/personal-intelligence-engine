# PIE Green Commands

PIE has multiple green lanes. They are intentionally separate so routine governance work does not require a full monolithic proof run every time.

## Command surface

```powershell
pie green status
pie green manifest
pie green governance
pie green governance-full
pie green full
pie green status

No tests are executed.

This command prints the current evidence state:

current branch
current commit
working tree clean/dirty state
latest canonical full-green freeze
latest governance-green freeze
governance freeze mode
governance freeze status
governance selftest count

Expected shape:

PIE_GREEN_STATUS
branch: main
commit: <sha>
working_tree: clean
latest_full_green: <path>
latest_full_green_summary: <path>
latest_governance_green: <path>
latest_governance_mode: <mode>
latest_governance_status: ok
latest_governance_selftest_count: <count>
pie green manifest

No green lane tests are executed.

This command validates the machine-readable green command manifest against the documented and implemented green command surface.

It checks:

manifest schema
command count
expected command names
expected modes
CLI routes
runner mode names
expected evidence filenames
lifecycle coverage declaration
green-lane governance rules

Expected shape:

PIE_GREEN_MANIFEST_VALIDATE_OK
manifest: C:\dev\pie\docs\PIE_GREEN_COMMANDS.manifest.json
commands: 5
pie green governance

Fast latest-governance lane.

This is the normal lane for current trusted-baseline governance work. It runs the currently relevant governance checks without rerunning the entire historic full-green stack.

Current scope:

cross-repo negative regression drift vector
trusted baseline enforcement
readable baseline governance report

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

Use this after changing trusted-baseline governance code, report generation, enforcement logic, or regression drift behavior.

pie green governance-full

Fast trusted-baseline lifecycle lane.

This lane proves the trusted-baseline lifecycle without chaining older stateful baseline selftests that reuse fixed baseline IDs in shared memory.

Current scope:

cross-repo negative regression drift vector
readable baseline governance report selftest

The readable report selftest proves the full trusted-baseline lifecycle internally:

promote
→ revoke
→ replace / supersede
→ lineage audit
→ readable governance report

Use this when the change affects the whole baseline lifecycle contract or when you want stronger evidence than pie green governance without paying for a full monolithic run.

pie green full

Canonical full-green delegate.

This delegates to:

scripts\FULL_GREEN_RUNNER_PIE_TIER0_v1.ps1

It produces the canonical full evidence freeze:

proofs/freeze/pie_tier0_green_<timestamp>/

Use this before major releases, after broad runner changes, or when the canonical full proof must be refreshed.

Rule of thumb

Use the smallest green lane that proves the change:

Change typeRecommended command
Check evidence state onlypie green status
Validate green command contractpie green manifest
Trusted-baseline report/enforcement tweakpie green governance
Trusted-baseline lifecycle semanticspie green governance-full
Broad runtime, packet, execution, or release proofpie green full
Evidence rule

Do not commit failed partial freezes.

If a green command fails:

inspect the stdout/stderr files in the generated freeze directory
fix forward
remove failed partial freeze evidence from git if accidentally staged
rerun the green lane
commit only the green runner/code and the latest successful freeze
Current green state checkpoint

At the time this document was added, PIE had:

canonical full green = sealed
readable baseline governance = sealed
fast governance green = sealed
governance-full lifecycle = isolated and green
green status = committed and clean
green manifest = enforceable command contract
