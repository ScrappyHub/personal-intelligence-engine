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

$ReceiptRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_lock"
$LatestReceiptPath = Join-Path $ReceiptRoot "latest_pie_green_lock_receipt.json"

if(-not (Test-Path -LiteralPath $LatestReceiptPath -PathType Leaf)){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_LATEST_POINTER_MISSING"
}

$Receipt = Get-JsonOrNull -Path $LatestReceiptPath
if($null -eq $Receipt){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_LOAD_FAIL"
}

if([string]$Receipt.schema -ne "pie.green.lock.receipt.v1"){
  throw ("PIE_GREEN_LOCK_RECEIPT_VERIFY_SCHEMA_BAD: " + [string]$Receipt.schema)
}

$Tag = [string]$Receipt.lock_tag
if([string]::IsNullOrWhiteSpace($Tag)){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_TAG_MISSING"
}

$LocalTagRef = ((git -C $RepoRoot rev-parse --verify ("refs/tags/" + $Tag)) -join "").Trim()
if([string]::IsNullOrWhiteSpace($LocalTagRef)){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_TAG_MISSING_LOCAL"
}

$TagTargetCommit = ((git -C $RepoRoot rev-list -n 1 $Tag) -join "").Trim()
if([string]::IsNullOrWhiteSpace($TagTargetCommit)){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_TAG_TARGET_MISSING"
}

if($TagTargetCommit -ne [string]$Receipt.lock_commit){
  throw ("PIE_GREEN_LOCK_RECEIPT_VERIFY_TAG_TARGET_BAD: " + $TagTargetCommit + " != " + [string]$Receipt.lock_commit)
}

$RemoteTagLine = ((git -C $RepoRoot ls-remote --tags origin ("refs/tags/" + $Tag)) -join "").Trim()
if([string]::IsNullOrWhiteSpace($RemoteTagLine)){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_TAG_MISSING_REMOTE"
}

$SnapshotPointer = [string]$Receipt.latest_final_snapshot_pointer
$Snapshot = Get-JsonOrNull -Path $SnapshotPointer
if($null -eq $Snapshot){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_SNAPSHOT_POINTER_BAD"
}

if([string]$Snapshot.schema -ne "pie.green.final.snapshot.v2"){
  throw ("PIE_GREEN_LOCK_RECEIPT_VERIFY_SNAPSHOT_SCHEMA_BAD: " + [string]$Snapshot.schema)
}

$AuditPath = [string]$Receipt.latest_green_audit_path
$Audit = Get-JsonOrNull -Path $AuditPath
if($null -eq $Audit){
  throw "PIE_GREEN_LOCK_RECEIPT_VERIFY_AUDIT_MISSING"
}

if([string]$Audit.status -ne "ok"){
  throw ("PIE_GREEN_LOCK_RECEIPT_VERIFY_AUDIT_STATUS_BAD: " + [string]$Audit.status)
}

if([int]$Audit.finding_count -ne 0){
  throw ("PIE_GREEN_LOCK_RECEIPT_VERIFY_AUDIT_FINDINGS_BAD: " + [string]$Audit.finding_count)
}

$Summary = [ordered]@{
  schema = "pie.green.lock.receipt.verify.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  receipt_path = $LatestReceiptPath
  lock_tag = $Tag
  lock_commit = [string]$Receipt.lock_commit
  remote_tag_present = $true
  snapshot_schema = [string]$Snapshot.schema
  audit_status = [string]$Audit.status
  audit_finding_count = [int]$Audit.finding_count
}

Write-Host "PIE_GREEN_LOCK_RECEIPT_VERIFY_OK" -ForegroundColor Green
Write-Host ("receipt: " + $LatestReceiptPath)
Write-Host ("tag: " + $Tag)
Write-Host ("lock_commit: " + [string]$Receipt.lock_commit)
