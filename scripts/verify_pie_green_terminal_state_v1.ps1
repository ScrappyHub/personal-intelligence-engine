param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if($Dir -and -not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Get-JsonOrThrow {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Code
  )

  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    throw $Code
  }

  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-LatestCompletedFreezeDir {
  param(
    [Parameter(Mandatory=$true)][string]$FreezeRoot,
    [Parameter(Mandatory=$true)][string]$Prefix
  )

  if(-not (Test-Path -LiteralPath $FreezeRoot -PathType Container)){
    return $null
  }

  return Get-ChildItem -LiteralPath $FreezeRoot -Directory |
    Where-Object {
      $_.Name -like ($Prefix + "*") -and
      (Test-Path -LiteralPath (Join-Path $_.FullName "FREEZE_SUMMARY.json") -PathType Leaf)
    } |
    Sort-Object Name -Descending |
    Select-Object -First 1
}

function Find-MatchingLockReceipt {
  param(
    [Parameter(Mandatory=$true)][string]$LockRoot,
    [Parameter(Mandatory=$true)][string]$LockedTag,
    [Parameter(Mandatory=$true)][string]$LockedCommitLong
  )

  if(-not (Test-Path -LiteralPath $LockRoot -PathType Container)){
    throw "PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_ROOT_MISSING"
  }

  $Files = Get-ChildItem -LiteralPath $LockRoot -File -Filter "pie_green_lock_receipt_*.json" |
    Sort-Object Name -Descending

  foreach($File in $Files){
    $Json = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
    if([string]$Json.schema -ne "pie.green.lock.receipt.v1"){ continue }
    if([string]$Json.lock_tag -ne $LockedTag){ continue }
    if([string]$Json.lock_commit -ne $LockedCommitLong){ continue }

    return [ordered]@{
      path = $File.FullName
      json = $Json
    }
  }

  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_MATCHING_LOCK_RECEIPT_MISSING: " + $LockedTag)
}

function Find-MatchingSnapshot {
  param(
    [Parameter(Mandatory=$true)][string]$SnapshotRoot,
    [Parameter(Mandatory=$true)][string]$LockedCommitShort
  )

  if(-not (Test-Path -LiteralPath $SnapshotRoot -PathType Container)){
    throw "PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_ROOT_MISSING"
  }

  $Files = Get-ChildItem -LiteralPath $SnapshotRoot -File -Filter "pie_green_final_snapshot_*.json" |
    Sort-Object Name -Descending

  foreach($File in $Files){
    $Json = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
    if([string]$Json.schema -ne "pie.green.final.snapshot.v2"){ continue }
    if([string]$Json.commit -ne $LockedCommitShort){ continue }
    if(-not [bool]$Json.git_status_clean){ continue }

    return [ordered]@{
      path = $File.FullName
      json = $Json
    }
  }

  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_MATCHING_SNAPSHOT_MISSING: " + $LockedCommitShort)
}

$TrackedStatus = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($TrackedStatus).Count -gt 0){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TRACKED_DIRTY: " + ($TrackedStatus -join " | "))
}

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$LockRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_lock"
$SnapshotRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_final_snapshot"
$TerminalRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_terminal"

$TerminalPointer = Join-Path $TerminalRoot "latest_pie_green_terminal_receipt.json"
$TerminalJson = Get-JsonOrThrow -Path $TerminalPointer -Code "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_POINTER_MISSING"

if([string]$TerminalJson.schema -ne "pie.green.terminal.receipt.v1"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_SCHEMA_BAD: " + [string]$TerminalJson.schema)
}

$LockedTag = [string]$TerminalJson.locked_tag
$LockedCommitLong = [string]$TerminalJson.locked_commit_long
$LockedCommitShort = ((git -C $RepoRoot rev-parse --short $LockedCommitLong) -join "").Trim()

if([string]::IsNullOrWhiteSpace($LockedTag)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_LOCK_TAG_MISSING"
}
if([string]::IsNullOrWhiteSpace($LockedCommitLong)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_LOCK_COMMIT_MISSING"
}
if([string]::IsNullOrWhiteSpace($LockedCommitShort)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_LOCK_COMMIT_SHORT_MISSING"
}

$LatestFull = Get-LatestCompletedFreezeDir -FreezeRoot $FreezeRoot -Prefix "pie_tier0_green_"
$LatestGov = Get-LatestCompletedFreezeDir -FreezeRoot $FreezeRoot -Prefix "pie_governance_green_"

if($null -eq $LatestFull){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_FULL_FREEZE_MISSING"
}
if($null -eq $LatestGov){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_GOV_FREEZE_MISSING"
}

$FullSummaryPath = Join-Path $LatestFull.FullName "FREEZE_SUMMARY.json"
$GovSummaryPath = Join-Path $LatestGov.FullName "FREEZE_SUMMARY.json"

$FullSummary = Get-JsonOrThrow -Path $FullSummaryPath -Code "PIE_GREEN_TERMINAL_STATE_VERIFY_FULL_SUMMARY_MISSING"
$GovSummary = Get-JsonOrThrow -Path $GovSummaryPath -Code "PIE_GREEN_TERMINAL_STATE_VERIFY_GOV_SUMMARY_MISSING"

if([string]$FullSummary.schema -ne "pie.tier0.full_green.summary.v1"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_FULL_SCHEMA_BAD: " + [string]$FullSummary.schema)
}
if([string]$FullSummary.status -ne "PIE_TIER0_FULL_GREEN_OK"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_FULL_STATUS_BAD: " + [string]$FullSummary.status)
}

if([string]$GovSummary.schema -ne "pie.governance.green.freeze.summary.v1"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_GOV_SCHEMA_BAD: " + [string]$GovSummary.schema)
}
if([string]$GovSummary.status -ne "ok"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_GOV_STATUS_BAD: " + [string]$GovSummary.status)
}
if([string]$GovSummary.mode -ne "trusted_baseline_lifecycle"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_GOV_MODE_BAD: " + [string]$GovSummary.mode)
}

$ResolvedLock = Find-MatchingLockReceipt -LockRoot $LockRoot -LockedTag $LockedTag -LockedCommitLong $LockedCommitLong
$ResolvedSnapshot = Find-MatchingSnapshot -SnapshotRoot $SnapshotRoot -LockedCommitShort $LockedCommitShort

$LockJson = $ResolvedLock.json
$SnapshotJson = $ResolvedSnapshot.json

if([string]$LockJson.lock_tag -ne $LockedTag){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_TAG_BAD: " + [string]$LockJson.lock_tag + " != " + $LockedTag)
}
if([string]$LockJson.lock_commit -ne $LockedCommitLong){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_COMMIT_BAD: " + [string]$LockJson.lock_commit + " != " + $LockedCommitLong)
}

if([string]$SnapshotJson.commit -ne $LockedCommitShort){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_COMMIT_BAD: " + [string]$SnapshotJson.commit + " != " + $LockedCommitShort)
}
if(-not [bool]$SnapshotJson.git_status_clean){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_NOT_CLEAN"
}
if([string]$SnapshotJson.latest_green_audit.status -ne "ok"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_AUDIT_BAD: " + [string]$SnapshotJson.latest_green_audit.status)
}
if([int]$SnapshotJson.latest_green_audit.finding_count -ne 0){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_AUDIT_FINDINGS_BAD: " + [string]$SnapshotJson.latest_green_audit.finding_count)
}
if([string]$SnapshotJson.latest_green_cli_contract_selftest.audit_status -ne "ok"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_CLI_CONTRACT_BAD: " + [string]$SnapshotJson.latest_green_cli_contract_selftest.audit_status)
}
if([int]$SnapshotJson.latest_green_cli_contract_selftest.audit_finding_count -ne 0){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_CLI_CONTRACT_FINDINGS_BAD: " + [string]$SnapshotJson.latest_green_cli_contract_selftest.audit_finding_count)
}

if([string]::IsNullOrWhiteSpace([string]$TerminalJson.resolved_final_snapshot_path)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_RESOLVED_SNAPSHOT_MISSING"
}
if(-not (Test-Path -LiteralPath ([string]$TerminalJson.resolved_final_snapshot_path) -PathType Leaf)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_RESOLVED_SNAPSHOT_BAD"
}

$ResolvedTerminalSnapshotCommit = ""
try {
  $ResolvedTerminalSnapshotJson = Get-Content -LiteralPath ([string]$TerminalJson.resolved_final_snapshot_path) -Raw | ConvertFrom-Json
  $ResolvedTerminalSnapshotCommit = [string]$ResolvedTerminalSnapshotJson.commit
}
catch {
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_RESOLVED_SNAPSHOT_PARSE_FAIL"
}

if($ResolvedTerminalSnapshotCommit -ne $LockedCommitShort){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_RESOLVED_SNAPSHOT_COMMIT_BAD: " + $ResolvedTerminalSnapshotCommit + " != " + $LockedCommitShort)
}

if([int]$TerminalJson.child_count -lt 2){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_CHILD_COUNT_BAD: " + [string]$TerminalJson.child_count)
}

$HeadShort = ((git -C $RepoRoot rev-parse --short HEAD) -join "").Trim()
$HeadLong = ((git -C $RepoRoot rev-parse HEAD) -join "").Trim()
$HeadTag = "pie_green_lock_" + $HeadShort

if([string]::IsNullOrWhiteSpace($HeadShort)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_HEAD_SHORT_MISSING"
}
if([string]::IsNullOrWhiteSpace($HeadLong)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_HEAD_LONG_MISSING"
}

$LocalHeadTag = ((git -C $RepoRoot tag --list $HeadTag) -join "").Trim()
if([string]::IsNullOrWhiteSpace($LocalHeadTag)){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_HEAD_TAG_MISSING_LOCAL: " + $HeadTag)
}

$LocalHeadTarget = ((git -C $RepoRoot rev-list -n 1 $HeadTag) -join "").Trim()
if($LocalHeadTarget -ne $HeadLong){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_HEAD_TAG_TARGET_BAD: " + $LocalHeadTarget + " != " + $HeadLong)
}

$RemoteHeadTag = ((git -C $RepoRoot ls-remote --tags origin ("refs/tags/" + $HeadTag)) -join "").Trim()
if([string]::IsNullOrWhiteSpace($RemoteHeadTag)){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_HEAD_TAG_MISSING_REMOTE: " + $HeadTag)
}

$RunRoot = Join-Path $RepoRoot "runs\pie_green_terminal_state_verify"
$CaseId = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$CaseRoot = Join-Path $RunRoot $CaseId
New-Item -ItemType Directory -Force -Path $CaseRoot | Out-Null

$Summary = [ordered]@{
  schema = "pie.green.terminal.state.verify.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  head_commit = $HeadShort
  head_commit_long = $HeadLong
  head_tag = $HeadTag
  baseline_lock_tag = $LockedTag
  baseline_lock_commit = $LockedCommitShort
  baseline_lock_commit_long = $LockedCommitLong
  resolved_lock_receipt_path = [string]$ResolvedLock.path
  resolved_snapshot_path = [string]$ResolvedSnapshot.path
  latest_terminal_receipt_pointer = $TerminalPointer
  latest_full_green = $LatestFull.FullName
  latest_governance_green = $LatestGov.FullName
}

$SummaryPath = Join-Path $CaseRoot "pie_green_terminal_state_verify_summary.json"
$LatestSummaryPath = Join-Path $RunRoot "latest_pie_green_terminal_state_verify_summary.json"

Write-Utf8NoBomLf -Path $SummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)
Write-Utf8NoBomLf -Path $LatestSummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)

Write-Host "PIE_GREEN_TERMINAL_STATE_VERIFY_OK" -ForegroundColor Green
Write-Host ("summary: " + $SummaryPath)
