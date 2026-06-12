param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $RepoRoot

$SnapshotRoot = Join-Path $RepoRoot "proofs\receipts\pie_green_final_snapshot"
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

function Get-LatestDir {
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Prefix
  )

  if(-not (Test-Path -LiteralPath $Root -PathType Container)){
    return $null
  }

  return Get-ChildItem -LiteralPath $Root -Directory |
    Where-Object { $_.Name -like ($Prefix + "*") } |
    Sort-Object Name -Descending |
    Select-Object -First 1
}

function Get-JsonOrNull {
  param([string]$Path)

  if([string]::IsNullOrWhiteSpace($Path)){ return $null }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $null }

  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

New-Item -ItemType Directory -Force -Path $SnapshotRoot | Out-Null

$Branch = ((git -C $RepoRoot rev-parse --abbrev-ref HEAD) -join "").Trim()
$Commit = ((git -C $RepoRoot rev-parse --short HEAD) -join "").Trim()
$GitStatus = @(git -C $RepoRoot status --short)

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$AuditRoot = Join-Path $RepoRoot "runs\green_audit"
$CliContractRoot = Join-Path $RepoRoot "runs\pie_green_cli_contract_selftest"

$LatestFull = Get-LatestDir -Root $FreezeRoot -Prefix "pie_tier0_green_"
$LatestGov = Get-LatestDir -Root $FreezeRoot -Prefix "pie_governance_green_"

$LatestAudit = $null
if(Test-Path -LiteralPath $AuditRoot -PathType Container){
  $LatestAudit = Get-ChildItem -LiteralPath $AuditRoot -File -Filter "green_audit_*.json" |
    Sort-Object Name -Descending |
    Select-Object -First 1
}

$LatestCliContract = $null
if(Test-Path -LiteralPath $CliContractRoot -PathType Container){
  $LatestCliContract = Get-ChildItem -LiteralPath $CliContractRoot -File -Filter "latest_pie_green_cli_contract_selftest_summary.json" |
    Select-Object -First 1
}

$FullSummaryPath = if($null -ne $LatestFull){ Join-Path $LatestFull.FullName "FREEZE_SUMMARY.json" } else { "" }
$GovSummaryPath = if($null -ne $LatestGov){ Join-Path $LatestGov.FullName "FREEZE_SUMMARY.json" } else { "" }

$FullSummary = Get-JsonOrNull -Path $FullSummaryPath
$GovSummary = Get-JsonOrNull -Path $GovSummaryPath
$AuditJson = if($null -ne $LatestAudit){ Get-JsonOrNull -Path $LatestAudit.FullName } else { $null }
$CliContractJson = if($null -ne $LatestCliContract){ Get-JsonOrNull -Path $LatestCliContract.FullName } else { $null }

$Snapshot = [ordered]@{
  schema = "pie.green.final.snapshot.v2"
  created_utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  branch = $Branch
  commit = $Commit
  git_status_clean = (@($GitStatus).Count -eq 0)
  git_status = @($GitStatus)

  latest_full_green = [ordered]@{
    freeze = $(if($null -ne $LatestFull){ $LatestFull.FullName } else { "" })
    summary = $FullSummaryPath
    summary_schema = $(if($null -ne $FullSummary){ [string]$FullSummary.schema } else { "" })
    status = $(if($null -ne $FullSummary -and $null -ne $FullSummary.PSObject.Properties["status"]){ [string]$FullSummary.status } else { "" })
    selftest_count = $(if($null -ne $FullSummary -and $null -ne $FullSummary.PSObject.Properties["selftest_count"]){ [int]$FullSummary.selftest_count } else { 0 })
    created_utc = $(if($null -ne $FullSummary -and $null -ne $FullSummary.PSObject.Properties["created_utc"]){ [string]$FullSummary.created_utc } else { "" })
  }

  latest_governance_green = [ordered]@{
    freeze = $(if($null -ne $LatestGov){ $LatestGov.FullName } else { "" })
    summary = $GovSummaryPath
    summary_schema = $(if($null -ne $GovSummary){ [string]$GovSummary.schema } else { "" })
    mode = $(if($null -ne $GovSummary -and $null -ne $GovSummary.PSObject.Properties["mode"]){ [string]$GovSummary.mode } else { "" })
    status = $(if($null -ne $GovSummary -and $null -ne $GovSummary.PSObject.Properties["status"]){ [string]$GovSummary.status } else { "" })
    selftest_count = $(if($null -ne $GovSummary -and $null -ne $GovSummary.PSObject.Properties["selftest_count"]){ [int]$GovSummary.selftest_count } else { 0 })
    created_utc = $(if($null -ne $GovSummary -and $null -ne $GovSummary.PSObject.Properties["created_utc"]){ [string]$GovSummary.created_utc } else { "" })
  }

  latest_green_audit = [ordered]@{
    path = $(if($null -ne $LatestAudit){ $LatestAudit.FullName } else { "" })
    status = $(if($null -ne $AuditJson -and $null -ne $AuditJson.PSObject.Properties["status"]){ [string]$AuditJson.status } else { "" })
    manifest_command_count = $(if($null -ne $AuditJson -and $null -ne $AuditJson.PSObject.Properties["manifest_command_count"]){ [int]$AuditJson.manifest_command_count } else { 0 })
    finding_count = $(if($null -ne $AuditJson -and $null -ne $AuditJson.PSObject.Properties["finding_count"]){ [int]$AuditJson.finding_count } else { 0 })
    created_utc = $(if($null -ne $AuditJson -and $null -ne $AuditJson.PSObject.Properties["created_utc"]){ [string]$AuditJson.created_utc } else { "" })
  }

  latest_green_cli_contract_selftest = [ordered]@{
    path = $(if($null -ne $LatestCliContract){ $LatestCliContract.FullName } else { "" })
    schema = $(if($null -ne $CliContractJson -and $null -ne $CliContractJson.PSObject.Properties["schema"]){ [string]$CliContractJson.schema } else { "" })
    audit_status = $(if($null -ne $CliContractJson -and $null -ne $CliContractJson.PSObject.Properties["audit_status"]){ [string]$CliContractJson.audit_status } else { "" })
    audit_finding_count = $(if($null -ne $CliContractJson -and $null -ne $CliContractJson.PSObject.Properties["audit_finding_count"]){ [int]$CliContractJson.audit_finding_count } else { 0 })
    step_count = $(if($null -ne $CliContractJson -and $null -ne $CliContractJson.PSObject.Properties["steps"]){ @($CliContractJson.steps).Count } else { 0 })
    created_utc = $(if($null -ne $CliContractJson -and $null -ne $CliContractJson.PSObject.Properties["created_utc"]){ [string]$CliContractJson.created_utc } else { "" })
  }
}

if(-not $Snapshot.git_status_clean){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_REQUIRES_CLEAN_TREE"
}
if([string]$Snapshot.latest_green_audit.status -ne "ok"){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_AUDIT_NOT_OK"
}
if([int]$Snapshot.latest_green_audit.finding_count -ne 0){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_AUDIT_FINDINGS_PRESENT"
}
if([string]$Snapshot.latest_green_cli_contract_selftest.audit_status -ne "ok"){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_CLI_CONTRACT_NOT_OK"
}
if([int]$Snapshot.latest_green_cli_contract_selftest.audit_finding_count -ne 0){
  throw "PIE_GREEN_FINAL_SNAPSHOT_V2_CLI_CONTRACT_FINDINGS_PRESENT"
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $SnapshotRoot ("pie_green_final_snapshot_" + $Stamp + ".json")
$LatestPath = Join-Path $SnapshotRoot "latest_pie_green_final_snapshot.json"

$Json = $Snapshot | ConvertTo-Json -Depth 50
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host "PIE_GREEN_FINAL_SNAPSHOT_V2_SCRIPT_OK" -ForegroundColor Green
Write-Host ("snapshot: " + $OutPath)
