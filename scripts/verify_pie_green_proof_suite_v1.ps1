param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

function Get-JsonOrNull {
  param([string]$Path)

  if([string]::IsNullOrWhiteSpace($Path)){ return $null }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $null }

  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

$SummaryRoot = Join-Path $RepoRoot "runs\pie_green_proof_suite_selftest"
$LatestSummaryPath = Join-Path $SummaryRoot "latest_pie_green_proof_suite_selftest_summary.json"

if(-not (Test-Path -LiteralPath $LatestSummaryPath -PathType Leaf)){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_LATEST_POINTER_MISSING"
}

$Summary = Get-JsonOrNull -Path $LatestSummaryPath
if($null -eq $Summary){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_LOAD_FAIL"
}

if([string]$Summary.schema -ne "pie.green.proof.suite.selftest.v1"){
  throw ("PIE_GREEN_PROOF_SUITE_VERIFY_SCHEMA_BAD: " + [string]$Summary.schema)
}

if(-not [bool]$Summary.tracked_state_unchanged){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_TRACKED_STATE_BAD"
}

$TrackedStatus = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($TrackedStatus).Count -gt 0){
  throw ("PIE_GREEN_PROOF_SUITE_VERIFY_TRACKED_DIRTY: " + ($TrackedStatus -join " | "))
}

$ExpectedNames = @(
  "verify_green_lock_receipt",
  "selftest_verify_green_lock_receipt",
  "verify_green_final_snapshot_v2",
  "selftest_verify_green_final_snapshot_v2",
  "verify_green_proof_chain",
  "selftest_verify_green_proof_chain"
)

$Steps = @($Summary.steps)
if(@($Steps).Count -ne $ExpectedNames.Count){
  throw ("PIE_GREEN_PROOF_SUITE_VERIFY_STEP_COUNT_BAD: " + [string]@($Steps).Count)
}

for($i = 0; $i -lt $ExpectedNames.Count; $i++){
  $Step = $Steps[$i]
  $ExpectedName = $ExpectedNames[$i]

  if([string]$Step.name -ne $ExpectedName){
    throw ("PIE_GREEN_PROOF_SUITE_VERIFY_STEP_NAME_BAD: " + [string]$Step.name + " != " + $ExpectedName)
  }

  if([int]$Step.exit_code -ne 0){
    throw ("PIE_GREEN_PROOF_SUITE_VERIFY_STEP_EXIT_BAD: " + $ExpectedName + " :: " + [string]$Step.exit_code)
  }

  $StdoutPath = [string]$Step.stdout_path
  $StderrPath = [string]$Step.stderr_path

  if([string]::IsNullOrWhiteSpace($StdoutPath) -or -not (Test-Path -LiteralPath $StdoutPath -PathType Leaf)){
    throw ("PIE_GREEN_PROOF_SUITE_VERIFY_STDOUT_MISSING: " + $ExpectedName)
  }

  if([string]::IsNullOrWhiteSpace($StderrPath) -or -not (Test-Path -LiteralPath $StderrPath -PathType Leaf)){
    throw ("PIE_GREEN_PROOF_SUITE_VERIFY_STDERR_MISSING: " + $ExpectedName)
  }

  $StdoutBytes = [int64](Get-Item -LiteralPath $StdoutPath).Length
  $StderrBytes = [int64](Get-Item -LiteralPath $StderrPath).Length

  if($StdoutBytes -le 0){
    throw ("PIE_GREEN_PROOF_SUITE_VERIFY_STDOUT_EMPTY: " + $ExpectedName)
  }

  if($StderrBytes -ne 0){
    throw ("PIE_GREEN_PROOF_SUITE_VERIFY_STDERR_NOT_EMPTY: " + $ExpectedName)
  }
}

Write-Host "PIE_GREEN_PROOF_SUITE_VERIFY_OK" -ForegroundColor Green
Write-Host ("summary: " + $LatestSummaryPath)
Write-Host ("step_count: " + [string]@($Steps).Count)
