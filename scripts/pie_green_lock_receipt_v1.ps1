param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Tag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

$OutRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_lock"
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

function Get-JsonOrNull {
  param([string]$Path)

  if([string]::IsNullOrWhiteSpace($Path)){ return $null }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $null }

  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

$TrackedStatus = @(git -C $RepoRoot status --short --untracked-files=no)
if(@($TrackedStatus).Count -gt 0){
  throw ("PIE_GREEN_LOCK_RECEIPT_REQUIRES_CLEAN_TREE: " + ($TrackedStatus -join " | "))
}

$HeadCommit = ((git -C $RepoRoot rev-parse --short HEAD) -join "").Trim()
$HeadCommitLong = ((git -C $RepoRoot rev-parse HEAD) -join "").Trim()
$HeadBranch = ((git -C $RepoRoot rev-parse --abbrev-ref HEAD) -join "").Trim()

$LocalTagRef = ((git -C $RepoRoot rev-parse --verify ("refs/tags/" + $Tag)) -join "").Trim()
if([string]::IsNullOrWhiteSpace($LocalTagRef)){
  throw "PIE_GREEN_LOCK_RECEIPT_TAG_MISSING_LOCAL"
}

$TagTargetCommit = ((git -C $RepoRoot rev-list -n 1 $Tag) -join "").Trim()
if([string]::IsNullOrWhiteSpace($TagTargetCommit)){
  throw "PIE_GREEN_LOCK_RECEIPT_TAG_TARGET_MISSING"
}

if($TagTargetCommit -ne $HeadCommitLong){
  throw ("PIE_GREEN_LOCK_RECEIPT_TAG_NOT_AT_HEAD: " + $TagTargetCommit + " != " + $HeadCommitLong)
}

$RemoteTagLine = ((git -C $RepoRoot ls-remote --tags origin ("refs/tags/" + $Tag)) -join "").Trim()
if([string]::IsNullOrWhiteSpace($RemoteTagLine)){
  throw "PIE_GREEN_LOCK_RECEIPT_TAG_MISSING_REMOTE"
}

$SnapshotPointer = Join-Path $RepoRoot "proofs\receipts\pie_green_final_snapshot\latest_pie_green_final_snapshot.json"
$SnapshotJson = Get-JsonOrNull -Path $SnapshotPointer
if($null -eq $SnapshotJson){
  throw "PIE_GREEN_LOCK_RECEIPT_SNAPSHOT_POINTER_MISSING"
}
if([string]$SnapshotJson.schema -ne "pie.green.final.snapshot.v2"){
  throw ("PIE_GREEN_LOCK_RECEIPT_SNAPSHOT_SCHEMA_BAD: " + [string]$SnapshotJson.schema)
}

$AuditRoot = Join-Path $RepoRoot "runs\green_audit"
$LatestAudit = $null
if(Test-Path -LiteralPath $AuditRoot -PathType Container){
  $LatestAudit = Get-ChildItem -LiteralPath $AuditRoot -File -Filter "green_audit_*.json" |
    Sort-Object Name -Descending |
    Select-Object -First 1
}
if($null -eq $LatestAudit){
  throw "PIE_GREEN_LOCK_RECEIPT_AUDIT_MISSING"
}

$AuditJson = Get-Content -LiteralPath $LatestAudit.FullName -Raw | ConvertFrom-Json
if([string]$AuditJson.status -ne "ok"){
  throw ("PIE_GREEN_LOCK_RECEIPT_AUDIT_STATUS_BAD: " + [string]$AuditJson.status)
}
if([int]$AuditJson.finding_count -ne 0){
  throw ("PIE_GREEN_LOCK_RECEIPT_AUDIT_FINDINGS_BAD: " + [string]$AuditJson.finding_count)
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$Receipt = [ordered]@{
  schema = "pie.green.lock.receipt.v1"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  head_branch = $HeadBranch
  head_commit = $HeadCommit
  head_commit_long = $HeadCommitLong
  lock_tag = $Tag
  lock_tag_ref = $LocalTagRef
  lock_commit = $TagTargetCommit
  remote_tag_present = $true
  latest_final_snapshot_pointer = $SnapshotPointer
  latest_final_snapshot_schema = [string]$SnapshotJson.schema
  latest_final_snapshot_commit = $(if($null -ne $SnapshotJson.PSObject.Properties["commit"]){ [string]$SnapshotJson.commit } else { "" })
  latest_green_audit_path = $LatestAudit.FullName
  latest_green_audit_status = [string]$AuditJson.status
  latest_green_audit_finding_count = [int]$AuditJson.finding_count
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("pie_green_lock_receipt_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_pie_green_lock_receipt.json"

$Json = $Receipt | ConvertTo-Json -Depth 50
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host "PIE_GREEN_LOCK_RECEIPT_OK" -ForegroundColor Green
Write-Host ("receipt: " + $OutPath)
