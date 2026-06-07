param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$AggregatePath,
  [Parameter(Mandatory=$true)][string]$BaselineId,
  [Parameter(Mandatory=$false)][string]$RegressionPath = "",
  [Parameter(Mandatory=$false)][string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$AggregatePath = (Resolve-Path -LiteralPath $AggregatePath).Path

if(-not [string]::IsNullOrWhiteSpace($RegressionPath)){
  $RegressionPath = (Resolve-Path -LiteralPath $RegressionPath).Path
}

$BaselineRoot = Join-Path $RepoRoot "memory\baselines\cross_repo"
$BaselineLog = Join-Path $BaselineRoot "baseline_promotions.ndjson"
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

if([string]::IsNullOrWhiteSpace($BaselineId)){
  throw "PIE_BASELINE_PROMOTE_ID_REQUIRED"
}

if($BaselineId -notmatch '^[a-zA-Z0-9._-]+$'){
  throw ("PIE_BASELINE_PROMOTE_ID_BAD: " + $BaselineId)
}

$Agg = Get-Content -LiteralPath $AggregatePath -Raw | ConvertFrom-Json

if($Agg.schema -ne "pie.cross.repo.replay.aggregate.v1"){
  throw "PIE_BASELINE_PROMOTE_AGG_SCHEMA_BAD"
}

if($Agg.status -ne "ok"){
  throw ("PIE_BASELINE_PROMOTE_AGG_STATUS_BAD: " + [string]$Agg.status)
}

if([int]$Agg.child_count -lt 1){
  throw "PIE_BASELINE_PROMOTE_AGG_CHILD_COUNT_BAD"
}

$RegressionStatus = ""
$RegressionFindingCount = $null

if(-not [string]::IsNullOrWhiteSpace($RegressionPath)){
  $Reg = Get-Content -LiteralPath $RegressionPath -Raw | ConvertFrom-Json

  if($Reg.schema -ne "pie.cross.repo.regression.replay.v1"){
    throw "PIE_BASELINE_PROMOTE_REG_SCHEMA_BAD"
  }

  $RegressionStatus = [string]$Reg.status
  $RegressionFindingCount = [int]$Reg.finding_count

  if($RegressionStatus -ne "match"){
    throw ("PIE_BASELINE_PROMOTE_REGRESSION_NOT_MATCH: " + $RegressionStatus)
  }

  if($RegressionFindingCount -ne 0){
    throw ("PIE_BASELINE_PROMOTE_REGRESSION_FINDINGS_NOT_ZERO: " + [string]$RegressionFindingCount)
  }
}

New-Item -ItemType Directory -Force -Path $BaselineRoot | Out-Null

$Dest = Join-Path $BaselineRoot ($BaselineId + ".aggregate.json")
Copy-Item -LiteralPath $AggregatePath -Destination $Dest -Force

$AggregateSha = Sha256File $AggregatePath
$DestSha = Sha256File $Dest

if($AggregateSha -ne $DestSha){
  throw "PIE_BASELINE_PROMOTE_COPY_HASH_MISMATCH"
}

$Promotion = [ordered]@{
  schema = "pie.cross.repo.baseline.promotion.v1"
  baseline_id = $BaselineId
  aggregate = $Dest
  aggregate_source = $AggregatePath
  aggregate_sha256 = $AggregateSha
  child_count = [int]$Agg.child_count
  regression = $RegressionPath
  regression_status = $RegressionStatus
  regression_finding_count = $RegressionFindingCount
  notes = $Notes
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$PromotionPath = Join-Path $BaselineRoot ($BaselineId + ".promotion.json")
$Json = $Promotion | ConvertTo-Json -Depth 40

Write-Utf8NoBomLf -Path $PromotionPath -Text $Json
[System.IO.File]::AppendAllText($BaselineLog,(($Promotion | ConvertTo-Json -Depth 40 -Compress) + "`n"),$Enc)

Write-Host ("PIE_CROSS_REPO_BASELINE_PROMOTE_OK: " + $PromotionPath) -ForegroundColor Green
Write-Host ("baseline_id: " + $BaselineId)
Write-Host ("aggregate_sha256: " + $AggregateSha)
