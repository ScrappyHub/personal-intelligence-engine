param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$RootBaselineId,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$BaselineRoot = Join-Path $RepoRoot "memory\baselines\cross_repo"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OutRoot = Join-Path $RunRoot "cross_repo_baseline_lineage_audit"
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

function Read-JsonOrNull {
  param([string]$Path)

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
  }

  return $null
}

function Load-Ndjson {
  param([string]$Path)

  $Rows = New-Object System.Collections.Generic.List[object]

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    foreach($Line in @(Get-Content -LiteralPath $Path)){
      if([string]::IsNullOrWhiteSpace($Line)){ continue }
      [void]$Rows.Add(($Line | ConvertFrom-Json))
    }
  }

  return $Rows.ToArray()
}

if([string]::IsNullOrWhiteSpace($RootBaselineId)){
  throw "PIE_BASELINE_LINEAGE_AUDIT_ROOT_REQUIRED"
}

if(-not (Test-Path -LiteralPath $BaselineRoot -PathType Container)){
  throw ("PIE_BASELINE_LINEAGE_AUDIT_ROOT_MISSING: " + $BaselineRoot)
}

$PromotionsLog = Join-Path $BaselineRoot "baseline_promotions.ndjson"
$RevocationsLog = Join-Path $BaselineRoot "baseline_revocations.ndjson"
$ReplacementsLog = Join-Path $BaselineRoot "baseline_replacements.ndjson"

$Promotions = @(Load-Ndjson $PromotionsLog)
$Revocations = @(Load-Ndjson $RevocationsLog)
$Replacements = @(Load-Ndjson $ReplacementsLog)

$Known = @{}
$Queue = New-Object System.Collections.Generic.Queue[string]
$Queue.Enqueue($RootBaselineId)
$Known[$RootBaselineId] = $true

# Walk replacement relationships forward and backward.
while($Queue.Count -gt 0){
  $Current = $Queue.Dequeue()

  foreach($R in $Replacements){
    $Old = [string]$R.old_baseline_id
    $New = [string]$R.new_baseline_id

    if($Old -eq $Current -and -not $Known.ContainsKey($New)){
      $Known[$New] = $true
      $Queue.Enqueue($New)
    }

    if($New -eq $Current -and -not $Known.ContainsKey($Old)){
      $Known[$Old] = $true
      $Queue.Enqueue($Old)
    }
  }
}

$Baselines = New-Object System.Collections.Generic.List[object]
$Edges = New-Object System.Collections.Generic.List[object]
$Problems = New-Object System.Collections.Generic.List[string]

foreach($BaselineId in @($Known.Keys | Sort-Object)){
  $PromotionPath = Join-Path $BaselineRoot ($BaselineId + ".promotion.json")
  $AggregatePath = Join-Path $BaselineRoot ($BaselineId + ".aggregate.json")
  $RevocationPath = Join-Path $BaselineRoot ($BaselineId + ".revocation.json")
  $ReplacementPath = Join-Path $BaselineRoot ($BaselineId + ".replacement.json")

  $Promotion = Read-JsonOrNull $PromotionPath
  $Revocation = Read-JsonOrNull $RevocationPath
  $Replacement = Read-JsonOrNull $ReplacementPath

  $Status = "active"
  $Reason = ""

  if($null -ne $Revocation){
    if($Revocation.schema -ne "pie.cross.repo.baseline.revocation.v1"){
      [void]$Problems.Add("bad_revocation_schema:" + $BaselineId)
    }
    elseif([bool]$Revocation.revoked -eq $true){
      $Status = "revoked"
      $Reason = [string]$Revocation.reason_code
    }
  }

  if($null -eq $Promotion){
    [void]$Problems.Add("missing_promotion:" + $BaselineId)
  }
  elseif($Promotion.schema -ne "pie.cross.repo.baseline.promotion.v1"){
    [void]$Problems.Add("bad_promotion_schema:" + $BaselineId)
  }

  if(-not (Test-Path -LiteralPath $AggregatePath -PathType Leaf)){
    [void]$Problems.Add("missing_aggregate:" + $BaselineId)
  }

  $PromotionAggregateSha = ""
  if($null -ne $Promotion){
    $PromotionAggregateSha = [string]$Promotion.aggregate_sha256
  }

  $ActualAggregateSha = Sha256OrEmpty $AggregatePath

  if(-not [string]::IsNullOrWhiteSpace($PromotionAggregateSha) -and -not [string]::IsNullOrWhiteSpace($ActualAggregateSha)){
    if($PromotionAggregateSha -ne $ActualAggregateSha){
      [void]$Problems.Add("aggregate_hash_mismatch:" + $BaselineId)
    }
  }

  [void]$Baselines.Add([pscustomobject][ordered]@{
    baseline_id = $BaselineId
    status = $Status
    reason_code = $Reason
    promotion = $PromotionPath
    promotion_sha256 = Sha256OrEmpty $PromotionPath
    aggregate = $AggregatePath
    aggregate_sha256 = $ActualAggregateSha
    promotion_aggregate_sha256 = $PromotionAggregateSha
    revocation = $RevocationPath
    revocation_sha256 = Sha256OrEmpty $RevocationPath
    replacement = $ReplacementPath
    replacement_sha256 = Sha256OrEmpty $ReplacementPath
  })
}

foreach($R in $Replacements){
  $Old = [string]$R.old_baseline_id
  $New = [string]$R.new_baseline_id

  if($Known.ContainsKey($Old) -or $Known.ContainsKey($New)){
    [void]$Edges.Add([pscustomobject][ordered]@{
      from = $Old
      to = $New
      type = "supersedes"
      old_revoked = [bool]$R.old_revoked
      old_aggregate_sha256 = [string]$R.old_aggregate_sha256
      new_aggregate_sha256 = [string]$R.new_aggregate_sha256
      replacement_sha256 = Sha256OrEmpty (Join-Path $BaselineRoot ($New + ".replacement.json"))
    })
  }
}

$Status = "ok"
if(@($Problems.ToArray()).Count -gt 0){
  $Status = "needs_review"
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("baseline_lineage_audit_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_baseline_lineage_audit.json"

$Audit = [ordered]@{
  schema = "pie.cross.repo.baseline.lineage.audit.v1"
  session_id = $SessionId
  root_baseline_id = $RootBaselineId
  status = $Status
  baseline_count = @($Baselines.ToArray()).Count
  edge_count = @($Edges.ToArray()).Count
  problems = $Problems.ToArray()
  baselines = $Baselines.ToArray()
  edges = $Edges.ToArray()
  logs = [ordered]@{
    promotions = $PromotionsLog
    promotions_sha256 = Sha256OrEmpty $PromotionsLog
    revocations = $RevocationsLog
    revocations_sha256 = Sha256OrEmpty $RevocationsLog
    replacements = $ReplacementsLog
    replacements_sha256 = Sha256OrEmpty $ReplacementsLog
  }
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Audit | ConvertTo-Json -Depth 80
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_CROSS_REPO_BASELINE_LINEAGE_AUDIT_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("status: " + $Status)
Write-Host ("baseline_count: " + [string]@($Baselines.ToArray()).Count)
Write-Host ("edge_count: " + [string]@($Edges.ToArray()).Count)
