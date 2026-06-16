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

$SummaryRoot = Join-Path $RepoRoot "runs\pie_green_proof_suite_verify_selftest"
$LatestSummaryPath = Join-Path $SummaryRoot "latest_pie_green_proof_suite_verify_selftest_summary.json"

if(-not (Test-Path -LiteralPath $LatestSummaryPath -PathType Leaf)){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_LATEST_POINTER_MISSING"
}

$Summary = Get-JsonOrNull -Path $LatestSummaryPath
if($null -eq $Summary){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_LOAD_FAIL"
}

if([string]$Summary.schema -ne "pie.green.proof.suite.verify.selftest.v1"){
  throw ("PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_SCHEMA_BAD: " + [string]$Summary.schema)
}

if(-not [bool]$Summary.tracked_state_unchanged){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_TRACKED_STATE_BAD"
}

$TrackedStatus = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($TrackedStatus).Count -gt 0){
  throw ("PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_TRACKED_DIRTY: " + ($TrackedStatus -join " | "))
}

$VerifierPath = [string]$Summary.verifier_path
if([string]::IsNullOrWhiteSpace($VerifierPath)){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_VERIFIER_PATH_EMPTY"
}
if(-not (Test-Path -LiteralPath $VerifierPath -PathType Leaf)){
  throw ("PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_VERIFIER_PATH_MISSING: " + $VerifierPath)
}

if([int]$Summary.exit_code -ne 0){
  throw ("PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_EXIT_CODE_BAD: " + [string]$Summary.exit_code)
}

$StdoutPath = [string]$Summary.stdout_path
$StderrPath = [string]$Summary.stderr_path

if([string]::IsNullOrWhiteSpace($StdoutPath) -or -not (Test-Path -LiteralPath $StdoutPath -PathType Leaf)){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_STDOUT_MISSING"
}

if([string]::IsNullOrWhiteSpace($StderrPath) -or -not (Test-Path -LiteralPath $StderrPath -PathType Leaf)){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_STDERR_MISSING"
}

$Stdout = [System.IO.File]::ReadAllText($StdoutPath,[System.Text.UTF8Encoding]::new($false))
$Stderr = [System.IO.File]::ReadAllText($StderrPath,[System.Text.UTF8Encoding]::new($false))

if($Stdout -notmatch 'PIE_GREEN_PROOF_SUITE_VERIFY_OK'){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_TOKEN_MISSING"
}

if(-not [string]::IsNullOrWhiteSpace($Stderr)){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_STDERR_NOT_EMPTY"
}

$StdoutBytes = [int64](Get-Item -LiteralPath $StdoutPath).Length
$StderrBytes = [int64](Get-Item -LiteralPath $StderrPath).Length

if($StdoutBytes -le 0){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_STDOUT_EMPTY"
}

if($StderrBytes -ne 0){
  throw "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_STDERR_BYTES_NOT_ZERO"
}

Write-Host "PIE_GREEN_PROOF_SUITE_VERIFY_SELFTEST_VERIFY_OK" -ForegroundColor Green
Write-Host ("summary: " + $LatestSummaryPath)
Write-Host ("verifier: " + $VerifierPath)
