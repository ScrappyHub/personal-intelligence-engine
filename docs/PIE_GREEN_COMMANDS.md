# PIE Green Commands

PIE has multiple green lanes. They are intentionally separate so routine govenance work does not require a full monolithic proof run every time.

## Command surface

```powershell
pie green status
pie green govenance
pie green govenance-full
pie green full
pie green status

No tests are executed.

This command prints the current evidence state:

current branch
current commit
working tree clean/dirty state
latest canonical full-green freeze
latest govenance-green freeze
govenance freeze mode
govenance freeze status
govenance selftest count

Use this before and after work to confirm the repo is clean and to see which evidence pack is currently latest.

Expected shape:

PIE_GREEN_STATUS
branch: main
commit: <sha>
working_tree: clean
latest_full_green: <path>
latest_full_green_summary: <path>
latest_govenance_green: <path>
latest_govenance_mode: <mode>
latest_govenance_status: ok
latest_govenance_selftest_count: <count>
pie green govenance

Fast latest-govenance lane.

This is the normal lane for current trusted-baseline govenance work. It runs the currently relevant govenance checks without rerunning the entire historic full-green stack.

Current scope:

cross-repo negative regression drift vector
trusted baseline enforcement
readable baseline govenance report

Evidence shape:

proofs/freeze/pie_govenance_green_<timestamp>/
  FREEZE_SUMMARY.json
  child_receipts.ndjson
  parse_gate_sha256s.txt
  sha256sums.txt
  cross_repo_regression_negative_stdout.txt
  cross_repo_regression_negative_stderr.txt
  cross_repo_baseline_enforce_stdout.txt
  cross_repo_baseline_enforce_stderr.txt
  cross_repo_baseline_govenance_report_stdout.txt
  cross_repo_baseline_govenance_report_stderr.txt

Use this after changing trusted-baseline govenance code, report generation, enforcement logic, or regression drift behavior.

pie green govenance-full

Fast trusted-baseline lifecycle lane.

This lane proves the trusted-baseline lifecycle without chaining older stateful baseline selftests that reuse fixed baseline IDs in shared memory.

Current scope:

cross-repo negative regression drift vector
readable baseline govenance report selftest

The readable report selftest proves the full trusted-baseline lifecycle intenally:

promote
→ revoke
→ replace / supersede
→ lineage audit
→ readable govenance report

Use this when the change affects the whole baseline lifecycle contract or when you want stronger evidence than pie green govenance without paying for a full monolithic run.

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
Trusted-baseline report/enforcement tweakpie green govenance
Trusted-baseline lifecycle semanticspie green govenance-full
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
readable baseline govenance = sealed
fast govenance green = sealed
govenance-full lifecycle = isolated and green
green status = committed and clean
n