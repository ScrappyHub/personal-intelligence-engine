param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$OldBaselineId,
  [Parameter(Mandatory=$true)][string]$NewBaselineId,
  [Parameter(Mandatory=$true)][string]$AggregatePath,
  [Parameter(Mandatory=$true)][string]$RegressionPath,
  [Parameter(Mandatory=$false)][switch]$RequireOldRevoked,
  [Parameter(Mandatory=$false)][string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$AggregatePath = (Resolve-Path -LiteralPath $AggregatePath).Path
$RegressionPath = (Resolve-Path -LiteralPath $RegressionPath).Path

$BaselineRoot = Join-Path $RepoRoot "memory\baselines\cross_repo"
$OldPromotion = Join-Path $BaselineRoot ($OldBaselineId + ".promotion.json")
$OldAggregate = Join-Path $BaselineRoot ($OldBaselineId + ".aggregate.json")
$OldRevocation = Join-Path $BaselineRoot ($OldBaselineId + ".revocation.json")
$NewPromotion = Join-Path $BaselineRoot ($NewBaselineId + ".promotion.json")
$NewAggregate = Join-Path $BaselineRoot ($NewBaselineId + ".aggregate.json")
$ReplacementPath = Join-Path $BaselineRoot ($NewBaselineId + ".replacement.json")
$ReplacementLog = Join-Path $BaselineRoot "baseline_replacements.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text
  )

  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  }

  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }

  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Sha256File {
  param([string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Sha256OrEmpty {
  param([string]$Path)
  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }
  return ""
}

if($OldBaselineId -notmatch '^[a-zA-Z0-9._-]+$'){
  throw ("PIE_BASELINE_REPLACE_OLD_ID_BAD: " + $OldBaselineId)
}

if($NewBaselineId -notmatch '^[a-zA-Z0-9._-]+$'){
  throw ("PIE_BASELINE_REPLACE_NEW_ID_BAD: " + $NewBaselineId)
}

if($OldBaselineId -eq $NewBaselineId){
  throw "PIE_BASELINE_REPLACE_IDS_MUST_DIFFER"
}

if(-not (Test-Path -LiteralPath $OldPromotion -PathType Leaf)){
  throw ("PIE_BASELINE_REPLACE_OLD_PROMOTION_MISSING: " + $OldPromotion)
}

if(-not (Test-Path -LiteralPath $OldAggregate -PathType Leaf)){
  throw ("PIE_BASELINE_REPLACE_OLD_AGGREGATE_MISSING: " + $OldAggregate)
}

$OldPromotionObj = Get-Content -LiteralPath $OldPromotion -Raw | ConvertFrom-Json

if($OldPromotionObj.schema -ne "pie.cross.repo.baseline.promotion.v1"){
  throw "PIE_BASELINE_REPLACE_OLD_PROMOTION_SCHEMA_BAD"
}

$OldAggregateSha = Sha256File $OldAggregate

if($OldAggregateSha -ne [string]$OldPromotionObj.aggregate_sha256){
  throw "PIE_BASELINE_REPLACE_OLD_HASH_MISMATCH"
}

$OldRevoked = $false
$OldRevocationSha = ""

if(Test-Path -LiteralPath $OldRevocation -PathType Leaf){
  $Rev = Get-Content -LiteralPath $OldRevocation -Raw | ConvertFrom-Json
  if($Rev.schema -ne "pie.cross.repo.baseline.revocation.v1"){
    throw "PIE_BASELINE_REPLACE_OLD_REVOCATION_SCHEMA_BAD"
  }
  if([bool]$Rev.revoked -eq $true){
    $OldRevoked = $true
    $OldRevocationSha = Sha256File $OldRevocation
  }
}

if($RequireOldRevoked -and -not $OldRevoked){
  throw "PIE_BASELINE_REPLACE_OLD_NOT_REVOKED"
}

$Agg = Get-Content -LiteralPath $AggregatePath -Raw | ConvertFrom-Json
if($Agg.schema -ne "pie.cross.repo.replay.aggregate.v1"){
  throw "PIE_BASELINE_REPLACE_NEW_AGG_SCHEMA_BAD"
}
if($Agg.status -ne "ok"){
  throw ("PIE_BASELINE_REPLACE_NEW_AGG_STATUS_BAD: " + [string]$Agg.status)
}
if([int]$Agg.child_count -lt 1){
  throw "PIE_BASELINE_REPLACE_NEW_AGG_CHILD_COUNT_BAD"
}

$Reg = Get-Content -LiteralPath $RegressionPath -Raw | ConvertFrom-Json
if($Reg.schema -ne "pie.cross.repo.regression.replay.v1"){
  throw "PIE_BASELINE_REPLACE_REG_SCHEMA_BAD"
}
if($Reg.status -ne "match"){
  throw ("PIE_BASELINE_REPLACE_REG_NOT_MATCH: " + [string]$Reg.status)
}
if([int]$Reg.finding_count -ne 0){
  throw ("PIE_BASELINE_REPLACE_REG_FINDINGS_NOT_ZERO: " + [string]$Reg.finding_count)
}

New-Item -ItemType Directory -Force -Path $BaselineRoot | Out-Null

Copy-Item -LiteralPath $AggregatePath -Destination $NewAggregate -Force

$NewAggSha = Sha256File $AggregatePath
$CopiedSha = Sha256File $NewAggregate

if($NewAggSha -ne $CopiedSha){
  throw "PIE_BASELINE_REPLACE_COPY_HASH_MISMATCH"
}

$NewPromotionObj = [ordered]@{
  schema = "pie.cross.repo.baseline.promotion.v1"
  baseline_id = $NewBaselineId
  aggregate = $NewAggregate
  aggregate_source = $AggregatePath
  aggregate_sha256 = $NewAggSha
  child_count = [int]$Agg.child_count
  regression = $RegressionPath
  regression_status = [string]$Reg.status
  regression_finding_count = [int]$Reg.finding_count
  notes = $Notes
  supersedes_baseline_id = $OldBaselineId
  supersedes_promotion = $OldPromotion
  supersedes_aggregate_sha256 = $OldAggregateSha
  supersedes_revocation = $OldRevocation
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$ReplacementObj = [ordered]@{
  schema = "pie.cross.repo.baseline.replacement.v1"
  old_baseline_id = $OldBaselineId
  old_promotion = $OldPromotion
  old_promotion_sha256 = Sha256File $OldPromotion
  old_aggregate = $OldAggregate
  old_aggregate_sha256 = $OldAggregateSha
  old_revoked = $OldRevoked
  old_revocation = $OldRevocation
  old_revocation_sha256 = $OldRevocationSha
  new_baseline_id = $NewBaselineId
  new_promotion = $NewPromotion
  new_aggregate = $NewAggregate
  new_aggregate_sha256 = $NewAggSha
  new_regression = $RegressionPath
  new_regression_status = [string]$Reg.status
  new_regression_finding_count = [int]$Reg.finding_count
  require_old_revoked = [bool]$RequireOldRevoked
  notes = $Notes
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $NewPromotion -Text ($NewPromotionObj | ConvertTo-Json -Depth 50)
Write-Utf8NoBomLf -Path $ReplacementPath -Text ($ReplacementObj | ConvertTo-Json -Depth 50)
[System.IO.File]::AppendAllText($ReplacementLog,(($ReplacementObj | ConvertTo-Json -Depth 50 -Compress) + "`n"),$Enc)

Write-Host ("PIE_CROSS_REPO_BASELINE_REPLACE_OK: " + $ReplacementPath) -ForegroundColor Green
Write-Host ("old_baseline_id: " + $OldBaselineId)
Write-Host ("new_baseline_id: " + $NewBaselineId)
Write-Host ("old_revoked: " + [string]$OldRevoked)
