param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$enc = New-Object System.Text.UTF8Encoding($false)

# Seals the state-integrity work of this line of development: proves the full battery is green
# (pie verify-full), captures the committed git HEAD, and writes a content-hashed freeze manifest.
# A freeze is only valid when backed by a passing gate (PIE LAW: claims require verifiable artifacts).

Write-Host "PIE_STATE_INTEGRITY_FREEZE_START" -ForegroundColor DarkCyan

# 1. Prove green.
$gateGreen = $false
if($SkipVerify){
  Write-Host "  (verify skipped by request; freeze will record verify=skipped)" -ForegroundColor Yellow
}
else {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\_RUN_pie_verify_full_v1.ps1") -RepoRoot $RepoRoot 2>&1 | Out-String
    $code = $LASTEXITCODE
  }
  finally { $ErrorActionPreference = $prev }
  if($code -ne 0 -or ($out -notmatch 'PIE_VERIFY_FULL_V1_GREEN')){
    throw "PIE_STATE_INTEGRITY_FREEZE_BLOCKED: verify-full is not green; refusing to seal"
  }
  $gateGreen = $true
  Write-Host "  gate: PIE_VERIFY_FULL_V1_GREEN" -ForegroundColor Green
}

# 2. Capture committed HEAD + working-tree cleanliness (source-tracked files only).
$head = (& git -C $RepoRoot rev-parse HEAD 2>$null)
if([string]::IsNullOrWhiteSpace($head)){ $head = "unknown" }
$dirtyTracked = @(& git -C $RepoRoot status --porcelain --untracked-files=no 2>$null | Where-Object { $_ -notmatch 'proofs/|test_vectors/|runs/' })

# 3. Build + write the freeze manifest (canonical, sorted-key compact) + a sha256 sidecar.
$manifest = [ordered]@{
  schema            = "pie.state.integrity.freeze.v1"
  frozen_utc        = (Get-Date).ToUniversalTime().ToString("o")
  git_head          = [string]$head
  verify            = $(if($SkipVerify){"skipped"}else{"PIE_VERIFY_FULL_V1_GREEN"})
  gate_green        = $gateGreen
  source_clean      = ($dirtyTracked.Count -eq 0)
  sealed_components = @(
    "B1 schema-migration foundation (version guard + fail-closed)",
    "B2 atomic-write foundation + run-seal adoption",
    "B3 transaction foundation + adoptions: run-seal, session-turn append, backup export",
    "B4 soak/restart harness (fault-injected recovery verified)",
    "B6 deterministic compaction with pinned-fact retention (foundation)",
    "B7 memory inspect + correct (provenance + safe supersede)",
    "engine adapters: ollama/llamacpp/onnx (opt-in) with shared persona + local/hosted parity",
    "pie verify-full consolidated release gate"
  )
  green_tokens      = @(
    "PIE_VERIFY_FULL_V1_GREEN","PIE_ENGINE_VERIFY_ALL_V1_GREEN","PIE_SOAK_V1_GREEN",
    "SELFTEST_PIE_ATOMIC_WRITE_V1_GREEN","SELFTEST_PIE_TXN_V1_GREEN","SELFTEST_PIE_MIGRATIONS_V1_GREEN",
    "SELFTEST_PIE_COMPACTION_V1_GREEN","SELFTEST_PIE_SESSION_TURN_RECOVERY_V1_GREEN",
    "SELFTEST_PIE_RUN_SEAL_TXN_V1_GREEN","PIE_SESSION_BACKUP_SELFTEST_OK"
  )
  deferred_next     = @(
    "OS-level process-kill / power-loss injection (vs simulated crash state)",
    "genuine multi-hour/multi-day soak with concurrent writers + second repo",
    "real-model semantic drift evaluation across model tiers (B5)",
    "compaction live-path unification onto PIE_CompactContext + pinned facts from memory",
    "hosted gateway implementation + tenant isolation (Phase 5)",
    "desktop release: migrations coverage, updater rollback, Windows signing (Phase 4)"
  )
  cap_rationale_doc = "docs/PIE_SESSION_CAP_2026-08-12.md"
}

$body = ($manifest | ConvertTo-Json -Depth 8)
$freezeDir = Join-Path $RepoRoot "freeze"
if(-not (Test-Path -LiteralPath $freezeDir -PathType Container)){ New-Item -ItemType Directory -Path $freezeDir -Force | Out-Null }
$freezePath = Join-Path $freezeDir "PIE_STATE_INTEGRITY_FREEZE_v1.json"
[System.IO.File]::WriteAllText($freezePath, ($body + "`n"), $enc)

$hash = [System.Security.Cryptography.SHA256]::Create()
try { $digest = ($hash.ComputeHash($enc.GetBytes($body + "`n")) | ForEach-Object { $_.ToString("x2") }) -join "" }
finally { $hash.Dispose() }
[System.IO.File]::WriteAllText((Join-Path $freezeDir "PIE_STATE_INTEGRITY_FREEZE_v1.sha256"), ("sha256:" + $digest + "  PIE_STATE_INTEGRITY_FREEZE_v1.json`n"), $enc)

Write-Host ("  git_head: " + $head) -ForegroundColor Cyan
Write-Host ("  freeze_sha256: sha256:" + $digest) -ForegroundColor Cyan
if($dirtyTracked.Count -gt 0){ Write-Host ("  NOTE: " + $dirtyTracked.Count + " tracked source file(s) uncommitted at freeze time") -ForegroundColor Yellow }
Write-Host "PIE_STATE_INTEGRITY_FREEZE_SEALED" -ForegroundColor Green
