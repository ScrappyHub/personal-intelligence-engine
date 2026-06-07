param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$BaselineId,
  [Parameter(Mandatory=$true)][string]$CandidateAggregate,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$CandidateAggregate = (Resolve-Path -LiteralPath $CandidateAggregate).Path

$BaselineRoot = Join-Path $RepoRoot "memory\baselines\cross_repo"
$BaselineAggregate = Join-Path $BaselineRoot ($BaselineId + ".aggregate.json")
$PromotionPath = Join-Path $BaselineRoot ($BaselineId + ".promotion.json")

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OutRoot = Join-Path $RunRoot "cross_repo_baseline_enforcement"
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

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }

  return ""
}

if([string]::IsNullOrWhiteSpace($BaselineId)){
  throw "PIE_BASELINE_ENFORCE_BASELINE_ID_REQUIRED"
}

if(-not (Test-Path -LiteralPath $BaselineAggregate -PathType Leaf)){
  throw ("PIE_BASELINE_ENFORCE_BASELINE_MISSING: " + $BaselineAggregate)
}

if(-not (Test-Path -LiteralPath $PromotionPath -PathType Leaf)){
  throw ("PIE_BASELINE_ENFORCE_PROMOTION_MISSING: " + $PromotionPath)
}

$Promotion = Get-Content -LiteralPath $PromotionPath -Raw | ConvertFrom-Json

if($Promotion.schema -ne "pie.cross.repo.baseline.promotion.v1"){
  throw "PIE_BASELINE_ENFORCE_PROMOTION_SCHEMA_BAD"
}

$ExpectedSha = [string]$Promotion.aggregate_sha256
$ActualSha = Sha256File $BaselineAggregate

if($ExpectedSha -ne $ActualSha){
  throw "PIE_BASELINE_ENFORCE_BASELINE_HASH_MISMATCH"
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

# Run regression replay using promoted baseline as baseline and candidate aggregate as candidate.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cross_repo_regression_replay_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -BaselineAggregate $BaselineAggregate `
  -CandidateAggregate $CandidateAggregate | Out-Host

if($LASTEXITCODE -ne 0){
  throw "PIE_BASELINE_ENFORCE_REGRESSION_FAIL"
}

$Regression = Join-Path $RunRoot "cross_repo_regression\latest_cross_repo_regression_replay.json"

if(-not (Test-Path -LiteralPath $Regression -PathType Leaf)){
  throw "PIE_BASELINE_ENFORCE_REGRESSION_MISSING"
}

$Reg = Get-Content -LiteralPath $Regression -Raw | ConvertFrom-Json

if($Reg.schema -ne "pie.cross.repo.regression.replay.v1"){
  throw "PIE_BASELINE_ENFORCE_REGRESSION_SCHEMA_BAD"
}

$Decision = "allow"
$Reason = "BASELINE_MATCH"

if($Reg.status -ne "match"){
  $Decision = "block"
  $Reason = "BASELINE_DRIFT"
}

if([int]$Reg.finding_count -ne 0){
  $Decision = "block"
  $Reason = "BASELINE_FINDINGS_PRESENT"
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("baseline_enforcement_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_baseline_enforcement.json"

$Enforcement = [ordered]@{
  schema = "pie.cross.repo.baseline.enforcement.v1"
  session_id = $SessionId
  baseline_id = $BaselineId
  baseline_aggregate = $BaselineAggregate
  baseline_sha256 = $ActualSha
  candidate_aggregate = $CandidateAggregate
  candidate_sha256 = Sha256File $CandidateAggregate
  promotion = $PromotionPath
  regression = $Regression
  regression_status = [string]$Reg.status
  regression_finding_count = [int]$Reg.finding_count
  decision = $Decision
  reason_code = $Reason
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Enforcement | ConvertTo-Json -Depth 50
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_CROSS_REPO_BASELINE_ENFORCE_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("decision: " + $Decision)
Write-Host ("reason_code: " + $Reason)
