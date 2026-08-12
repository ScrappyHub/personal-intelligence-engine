param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [switch]$SkipSoak
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Full-system release gate. Runs the whole verification battery as one command and requires every
# part green: engine + persona + Tier-0 + state (verify-engines), session turn crash-recovery,
# backup export/verify/restore, and a soak smoke. Emits PIE_VERIFY_FULL_V1_GREEN with a receipt.

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts  = Join-Path $RepoRoot "scripts"
$results  = New-Object System.Collections.Generic.List[object]

function Run-Part([string]$id,[string]$script,[string[]]$cargs,[string]$greenToken){
  $p = Join-Path $Scripts $script
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ $results.Add([ordered]@{ id=$id; status="fail"; detail="missing" }); Write-Host ("  [FAIL] " + $id + " :: missing") -ForegroundColor Red; return }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p @cargs 2>&1 | Out-String; $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $prev }
  if($code -eq 0 -and $out -match [regex]::Escape($greenToken)){
    $results.Add([ordered]@{ id=$id; status="pass"; detail=$greenToken })
    Write-Host ("  [PASS] " + $id) -ForegroundColor Green
  } else {
    $tail = @($out -split "`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1
    $results.Add([ordered]@{ id=$id; status="fail"; detail=([string]$tail).Trim() })
    Write-Host ("  [FAIL] " + $id + " :: " + ([string]$tail).Trim()) -ForegroundColor Red
  }
}

Write-Host "PIE_VERIFY_FULL_START" -ForegroundColor DarkCyan

Run-Part "engines"          "_RUN_pie_engine_verify_all_v1.ps1"      @("-RepoRoot",$RepoRoot,"-IncludeTier0") "PIE_ENGINE_VERIFY_ALL_V1_GREEN"
Run-Part "session_recovery" "_selftest_pie_session_turn_recovery_v1.ps1" @("-RepoRoot",$RepoRoot)            "SELFTEST_PIE_SESSION_TURN_RECOVERY_V1_GREEN"
Run-Part "backup"           "selftest_pie_session_backup_v1.ps1"     @("-RepoRoot",$RepoRoot)                 "PIE_SESSION_BACKUP_SELFTEST_OK"
if(-not $SkipSoak){
  Run-Part "soak"           "_RUN_pie_soak_v1.ps1"                   @("-RepoRoot",$RepoRoot,"-FaultEvery","3") "PIE_SOAK_V1_GREEN"
}

$fail = @($results | Where-Object { $_.status -eq "fail" }).Count
$pass = @($results | Where-Object { $_.status -eq "pass" }).Count

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
$outDir = Join-Path $RepoRoot "runs\verify_full"
if(-not (Test-Path -LiteralPath $outDir -PathType Container)){ New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$enc = New-Object System.Text.UTF8Encoding($false)
$receipt = [ordered]@{ schema="pie.verify.full.report.v1"; generated_utc=(Get-Date).ToUniversalTime().ToString("o"); totals=[ordered]@{ pass=$pass; fail=$fail }; green=($fail -eq 0); parts=$results }
$json = ($receipt | ConvertTo-Json -Depth 8)
[System.IO.File]::WriteAllText((Join-Path $outDir ($stamp + ".json")), $json, $enc)
[System.IO.File]::WriteAllText((Join-Path $outDir "latest.json"), $json, $enc)

Write-Host ("SUMMARY pass=" + $pass + " fail=" + $fail) -ForegroundColor Cyan
if($fail -eq 0){ Write-Host "PIE_VERIFY_FULL_V1_GREEN" -ForegroundColor Green }
else { throw ("PIE_VERIFY_FULL_V1_FAIL: " + $fail + " part(s) failed; see runs\verify_full\latest.json") }
