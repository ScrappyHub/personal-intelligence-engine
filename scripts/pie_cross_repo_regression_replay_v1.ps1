param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$BaselineAggregate,
  [Parameter(Mandatory=$true)][string]$CandidateAggregate,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$BaselineAggregate = (Resolve-Path -LiteralPath $BaselineAggregate).Path
$CandidateAggregate = (Resolve-Path -LiteralPath $CandidateAggregate).Path

$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OutRoot = Join-Path $RunRoot "cross_repo_regression"
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

function Child-Key {
  param([object]$Child)

  return ([string]$Child.repo).ToLowerInvariant() + "|" + ([string]$Child.capability_id).ToLowerInvariant() + "|" + ([string]$Child.command).ToLowerInvariant()
}

$Base = Get-Content -LiteralPath $BaselineAggregate -Raw | ConvertFrom-Json
$Cand = Get-Content -LiteralPath $CandidateAggregate -Raw | ConvertFrom-Json

if($Base.schema -ne "pie.cross.repo.replay.aggregate.v1"){
  throw "PIE_CROSS_REPO_REGRESSION_BASELINE_SCHEMA_BAD"
}

if($Cand.schema -ne "pie.cross.repo.replay.aggregate.v1"){
  throw "PIE_CROSS_REPO_REGRESSION_CANDIDATE_SCHEMA_BAD"
}

$Findings = New-Object System.Collections.Generic.List[object]

if([int]$Base.child_count -ne [int]$Cand.child_count){
  [void]$Findings.Add([pscustomobject][ordered]@{
    code = "child_count_changed"
    baseline = [int]$Base.child_count
    candidate = [int]$Cand.child_count
  })
}

$BaseMap = @{}
foreach($C in @($Base.children)){
  $K = Child-Key $C
  if(-not $BaseMap.ContainsKey($K)){
    $BaseMap[$K] = $C
  }
}

$CandMap = @{}
foreach($C in @($Cand.children)){
  $K = Child-Key $C
  if(-not $CandMap.ContainsKey($K)){
    $CandMap[$K] = $C
  }
}

foreach($K in @($BaseMap.Keys | Sort-Object)){
  if(-not $CandMap.ContainsKey($K)){
    [void]$Findings.Add([pscustomobject][ordered]@{
      code = "missing_candidate_child"
      key = $K
    })
    continue
  }

  $B = $BaseMap[$K]
  $C = $CandMap[$K]

  if([string]$B.stdout_sha256 -ne [string]$C.stdout_sha256){
    [void]$Findings.Add([pscustomobject][ordered]@{
      code = "stdout_hash_changed"
      key = $K
      baseline = [string]$B.stdout_sha256
      candidate = [string]$C.stdout_sha256
    })
  }

  if([string]$B.stderr_sha256 -ne [string]$C.stderr_sha256){
    [void]$Findings.Add([pscustomobject][ordered]@{
      code = "stderr_hash_changed"
      key = $K
      baseline = [string]$B.stderr_sha256
      candidate = [string]$C.stderr_sha256
    })
  }

  if([string]$B.snapshot_diff_sha256 -ne [string]$C.snapshot_diff_sha256){
    [void]$Findings.Add([pscustomobject][ordered]@{
      code = "snapshot_diff_hash_changed"
      key = $K
      baseline = [string]$B.snapshot_diff_sha256
      candidate = [string]$C.snapshot_diff_sha256
    })
  }
}

foreach($K in @($CandMap.Keys | Sort-Object)){
  if(-not $BaseMap.ContainsKey($K)){
    [void]$Findings.Add([pscustomobject][ordered]@{
      code = "new_candidate_child"
      key = $K
    })
  }
}

$Status = "match"
if(@($Findings.ToArray()).Count -gt 0){
  $Status = "drift"
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("cross_repo_regression_replay_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_cross_repo_regression_replay.json"

$Result = [ordered]@{
  schema = "pie.cross.repo.regression.replay.v1"
  session_id = $SessionId
  baseline_aggregate = $BaselineAggregate
  baseline_sha256 = Sha256File $BaselineAggregate
  candidate_aggregate = $CandidateAggregate
  candidate_sha256 = Sha256File $CandidateAggregate
  status = $Status
  finding_count = @($Findings.ToArray()).Count
  findings = $Findings.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Result | ConvertTo-Json -Depth 80
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_CROSS_REPO_REGRESSION_REPLAY_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("status: " + $Status)
Write-Host ("finding_count: " + [string]@($Findings.ToArray()).Count)
