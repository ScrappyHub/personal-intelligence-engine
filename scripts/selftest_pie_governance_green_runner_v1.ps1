param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\GOVERNANCE_GREEN_RUNNER_PIE_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Mode "latest_governance" `
  -TimeoutSeconds 480 | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_GOVERNANCE_GREEN_RUNNER_CHILD_FAIL"
}

$Latest = Get-ChildItem (Join-Path $RepoRoot "proofs\freeze") -Directory |
  Where-Object { $_.Name -like "pie_governance_green_*" } |
  Sort-Object Name -Descending |
  Select-Object -First 1

if($null -eq $Latest){
  throw "PIE_GOVERNANCE_GREEN_RUNNER_FREEZE_MISSING"
}

$SummaryPath = Join-Path $Latest.FullName "FREEZE_SUMMARY.json"
$SumsPath = Join-Path $Latest.FullName "sha256sums.txt"
$ReportStdout = Join-Path $Latest.FullName "cross_repo_baseline_governance_report_stdout.txt"
$ReportStderr = Join-Path $Latest.FullName "cross_repo_baseline_governance_report_stderr.txt"
$EnforceStdout = Join-Path $Latest.FullName "cross_repo_baseline_enforce_stdout.txt"
$NegativeStdout = Join-Path $Latest.FullName "cross_repo_regression_negative_stdout.txt"

foreach($P in @($SummaryPath,$SumsPath,$ReportStdout,$ReportStderr,$EnforceStdout,$NegativeStdout)){
  if(-not (Test-Path -LiteralPath $P -PathType Leaf)){
    throw ("PIE_GOVERNANCE_GREEN_RUNNER_EXPECTED_FILE_MISSING: " + $P)
  }
}

$Summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json

if($Summary.schema -ne "pie.governance.green.freeze.summary.v1"){
  throw "PIE_GOVERNANCE_GREEN_RUNNER_SUMMARY_SCHEMA_BAD"
}

if($Summary.status -ne "ok"){
  throw "PIE_GOVERNANCE_GREEN_RUNNER_STATUS_BAD"
}

if($Summary.mode -ne "latest_governance"){
  throw "PIE_GOVERNANCE_GREEN_RUNNER_MODE_BAD"
}

Write-Host "PIE_GOVERNANCE_GREEN_RUNNER_SELFTEST_OK" -ForegroundColor Green
