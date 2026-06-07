param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$BaselineId,
  [Parameter(Mandatory=$true)][string]$ReasonCode,
  [Parameter(Mandatory=$false)][string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$BaselineRoot = Join-Path $RepoRoot "memory\baselines\cross_repo"
$PromotionPath = Join-Path $BaselineRoot ($BaselineId + ".promotion.json")
$BaselineAggregate = Join-Path $BaselineRoot ($BaselineId + ".aggregate.json")
$RevocationPath = Join-Path $BaselineRoot ($BaselineId + ".revocation.json")
$RevocationLog = Join-Path $BaselineRoot "baseline_revocations.ndjson"
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

function Sha256OrEmpty {
  param([string]$Path)

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }

  return ""
}

if([string]::IsNullOrWhiteSpace($BaselineId)){
  throw "PIE_BASELINE_REVOKE_ID_REQUIRED"
}

if($BaselineId -notmatch '^[a-zA-Z0-9._-]+$'){
  throw ("PIE_BASELINE_REVOKE_ID_BAD: " + $BaselineId)
}

if([string]::IsNullOrWhiteSpace($ReasonCode)){
  throw "PIE_BASELINE_REVOKE_REASON_REQUIRED"
}

if($ReasonCode -notmatch '^[A-Z0-9_]+$'){
  throw ("PIE_BASELINE_REVOKE_REASON_BAD: " + $ReasonCode)
}

if(-not (Test-Path -LiteralPath $PromotionPath -PathType Leaf)){
  throw ("PIE_BASELINE_REVOKE_PROMOTION_MISSING: " + $PromotionPath)
}

$Promotion = Get-Content -LiteralPath $PromotionPath -Raw | ConvertFrom-Json

if($Promotion.schema -ne "pie.cross.repo.baseline.promotion.v1"){
  throw "PIE_BASELINE_REVOKE_PROMOTION_SCHEMA_BAD"
}

$Revocation = [ordered]@{
  schema = "pie.cross.repo.baseline.revocation.v1"
  baseline_id = $BaselineId
  reason_code = $ReasonCode
  notes = $Notes
  promotion = $PromotionPath
  promotion_sha256 = Sha256OrEmpty $PromotionPath
  aggregate = $BaselineAggregate
  aggregate_sha256 = Sha256OrEmpty $BaselineAggregate
  previous_promotion_aggregate_sha256 = [string]$Promotion.aggregate_sha256
  revoked = $true
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Revocation | ConvertTo-Json -Depth 40
Write-Utf8NoBomLf -Path $RevocationPath -Text $Json
[System.IO.File]::AppendAllText($RevocationLog,(($Revocation | ConvertTo-Json -Depth 40 -Compress) + "`n"),$Enc)

Write-Host ("PIE_CROSS_REPO_BASELINE_REVOKE_OK: " + $RevocationPath) -ForegroundColor Green
Write-Host ("baseline_id: " + $BaselineId)
Write-Host ("reason_code: " + $ReasonCode)
