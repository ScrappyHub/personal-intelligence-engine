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

$SnapshotRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_final_snapshot"
$LatestSnapshotPath = Join-Path $SnapshotRoot "latest_pie_green_final_snapshot.json"

if(-not (Test-Path -LiteralPath $LatestSnapshotPath -PathType Leaf)){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_LATEST_POINTER_MISSING"
}

$Snapshot = Get-JsonOrNull -Path $LatestSnapshotPath
if($null -eq $Snapshot){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_LOAD_FAIL"
}

if([string]$Snapshot.schema -ne "pie.green.final.snapshot.v2"){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_SCHEMA_BAD: " + [string]$Snapshot.schema)
}

if(-not [bool]$Snapshot.git_status_clean){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_GIT_STATUS_NOT_CLEAN"
}

$TrackedStatus = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($TrackedStatus).Count -gt 0){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_TRACKED_DIRTY: " + ($TrackedStatus -join " | "))
}

$Full = $Snapshot.latest_full_green
$Gov = $Snapshot.latest_governance_green
$Audit = $Snapshot.latest_green_audit
$CliContract = $Snapshot.latest_green_cli_contract_selftest

if([string]$Full.status -ne "PIE_TIER0_FULL_GREEN_OK"){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_FULL_STATUS_BAD: " + [string]$Full.status)
}

if([string]$Gov.status -ne "ok"){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_GOV_STATUS_BAD: " + [string]$Gov.status)
}

if([string]$Gov.mode -ne "trusted_baseline_lifecycle"){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_GOV_MODE_BAD: " + [string]$Gov.mode)
}

if([string]$Audit.status -ne "ok"){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_AUDIT_STATUS_BAD: " + [string]$Audit.status)
}

if([int]$Audit.finding_count -ne 0){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_AUDIT_FINDINGS_BAD: " + [string]$Audit.finding_count)
}

if([string]$CliContract.schema -ne "pie.green.cli.contract.selftest.v1"){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_CLI_CONTRACT_SCHEMA_BAD: " + [string]$CliContract.schema)
}

if([string]$CliContract.audit_status -ne "ok"){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_CLI_CONTRACT_STATUS_BAD: " + [string]$CliContract.audit_status)
}

if([int]$CliContract.audit_finding_count -ne 0){
  throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_CLI_CONTRACT_FINDINGS_BAD: " + [string]$CliContract.audit_finding_count)
}

$FullFreeze = [string]$Full.freeze
$GovFreeze = [string]$Gov.freeze
$AuditPath = [string]$Audit.path
$CliContractPath = [string]$CliContract.path

foreach($RequiredPath in @($FullFreeze,$GovFreeze,$AuditPath,$CliContractPath)){
  if([string]::IsNullOrWhiteSpace($RequiredPath)){
    throw "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_REQUIRED_PATH_EMPTY"
  }
  if(-not (Test-Path -LiteralPath $RequiredPath)){
    throw ("PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_REQUIRED_PATH_MISSING: " + $RequiredPath)
  }
}

$Summary = [ordered]@{
  schema = "pie.green.final.snapshot.verify.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  latest_snapshot_path = $LatestSnapshotPath
  snapshot_schema = [string]$Snapshot.schema
  full_status = [string]$Full.status
  governance_status = [string]$Gov.status
  governance_mode = [string]$Gov.mode
  audit_status = [string]$Audit.status
  audit_finding_count = [int]$Audit.finding_count
  cli_contract_schema = [string]$CliContract.schema
  cli_contract_status = [string]$CliContract.audit_status
  cli_contract_finding_count = [int]$CliContract.audit_finding_count
}

Write-Host "PIE_GREEN_FINAL_SNAPSHOT_V2_VERIFY_OK" -ForegroundColor Green
Write-Host ("snapshot: " + $LatestSnapshotPath)
Write-Host ("full_status: " + [string]$Summary.full_status)
Write-Host ("governance_status: " + [string]$Summary.governance_status)
Write-Host ("audit_status: " + [string]$Summary.audit_status)
Write-Host ("cli_contract_status: " + [string]$Summary.cli_contract_status)
