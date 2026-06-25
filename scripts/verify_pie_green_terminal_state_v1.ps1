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

$TrackedStatus = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($TrackedStatus).Count -gt 0){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TRACKED_DIRTY: " + ($TrackedStatus -join " | "))
}

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$LockPointer = Join-Path $RepoRoot "proofs\receipts\pie_green_lock\latest_pie_green_lock_receipt.json"
$SnapshotPointer = Join-Path $RepoRoot "proofs\receipts\pie_green_final_snapshot\latest_pie_green_final_snapshot.json"
$TerminalPointer = Join-Path $RepoRoot "proofs\receipts\pie_green_terminal\latest_pie_green_terminal_receipt.json"

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
$LockJson = Get-JsonOrThrow -Path $LockPointer -Code "PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_POINTER_MISSING"
$SnapshotJson = Get-JsonOrThrow -Path $SnapshotPointer -Code "PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_POINTER_MISSING"
$TerminalJson = Get-JsonOrThrow -Path $TerminalPointer -Code "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_POINTER_MISSING"

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

if([string]$LockJson.schema -ne "pie.green.lock.receipt.v1"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_SCHEMA_BAD: " + [string]$LockJson.schema)
}
if([string]$SnapshotJson.schema -ne "pie.green.final.snapshot.v2"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_SNAPSHOT_SCHEMA_BAD: " + [string]$SnapshotJson.schema)
}
if([string]$TerminalJson.schema -ne "pie.green.terminal.receipt.v1"){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_SCHEMA_BAD: " + [string]$TerminalJson.schema)
}

$LockedTag = [string]$LockJson.lock_tag
$LockedCommitLong = [string]$LockJson.lock_commit
$LockedCommitShort = ((git -C $RepoRoot rev-parse --short $LockedCommitLong) -join "").Trim()

if([string]::IsNullOrWhiteSpace($LockedTag)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_TAG_MISSING"
}
if([string]::IsNullOrWhiteSpace($LockedCommitLong)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_COMMIT_MISSING"
}
if([string]::IsNullOrWhiteSpace($LockedCommitShort)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_LOCK_COMMIT_SHORT_MISSING"
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

if([string]$TerminalJson.locked_tag -ne $LockedTag){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_LOCK_TAG_BAD: " + [string]$TerminalJson.locked_tag + " != " + $LockedTag)
}
if([string]$TerminalJson.locked_commit_long -ne $LockedCommitLong){
  throw ("PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_LOCK_COMMIT_BAD: " + [string]$TerminalJson.locked_commit_long + " != " + $LockedCommitLong)
}
if([string]::IsNullOrWhiteSpace([string]$TerminalJson.resolved_final_snapshot_path)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_RESOLVED_SNAPSHOT_MISSING"
}
if(-not (Test-Path -LiteralPath ([string]$TerminalJson.resolved_final_snapshot_path) -PathType Leaf)){
  throw "PIE_GREEN_TERMINAL_STATE_VERIFY_TERMINAL_RESOLVED_SNAPSHOT_BAD"
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
  latest_full_green = $LatestFull.FullName
  latest_governance_green = $LatestGov.FullName
  latest_lock_receipt_pointer = $LockPointer
  latest_snapshot_pointer = $SnapshotPointer
  latest_terminal_receipt_pointer = $TerminalPointer
}

$SummaryPath = Join-Path $CaseRoot "pie_green_terminal_state_verify_summary.json"
$LatestSummaryPath = Join-Path $RunRoot "latest_pie_green_terminal_state_verify_summary.json"

Write-Utf8NoBomLf -Path $SummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)
Write-Utf8NoBomLf -Path $LatestSummaryPath -Text ($Summary | ConvertTo-Json -Depth 50)

Write-Host "PIE_GREEN_TERMINAL_STATE_VERIFY_OK" -ForegroundColor Green
Write-Host ("summary: " + $SummaryPath)
