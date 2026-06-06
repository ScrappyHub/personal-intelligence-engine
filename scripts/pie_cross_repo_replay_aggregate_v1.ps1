param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$ExecRoot = Join-Path $RunRoot "cross_repo_execution"
$ReceiptPath = Join-Path $ExecRoot "cross_repo_execution_receipts.ndjson"
$OutRoot = Join-Path $RunRoot "cross_repo_replay"
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

function Get-Sha256OrEmpty {
  param([AllowEmptyString()][string]$Path)

  if([string]::IsNullOrWhiteSpace($Path)){ return "" }

  if(Test-Path -LiteralPath $Path -PathType Leaf){
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }

  return ""
}

function Get-LatestFile {
  param(
    [Parameter(Mandatory=$true)][string]$Dir,
    [Parameter(Mandatory=$true)][string]$Filter
  )

  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){
    return ""
  }

  $Latest = Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue |
    Sort-Object @{ Expression = "LastWriteTimeUtc"; Descending = $true }, @{ Expression = "Name"; Descending = $true } |
    Select-Object -First 1

  if($null -eq $Latest){ return "" }

  return $Latest.FullName
}

if(-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){
  throw ("PIE_CROSS_REPO_REPLAY_RECEIPTS_MISSING: " + $ReceiptPath)
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$ChildRows = New-Object System.Collections.Generic.List[object]
$Problems = New-Object System.Collections.Generic.List[string]

foreach($Line in @(Get-Content -LiteralPath $ReceiptPath)){
  if([string]::IsNullOrWhiteSpace($Line)){ continue }

  $R = $Line | ConvertFrom-Json
  $ChildSessionId = [string]$R.child_session_id
  $ChildRoot = Join-Path $RepoRoot ("runs\" + $ChildSessionId)

  if(-not (Test-Path -LiteralPath $ChildRoot -PathType Container)){
    [void]$Problems.Add("missing_child_run:" + $ChildSessionId)
    continue
  }

  $Stdout = Get-LatestFile -Dir (Join-Path $ChildRoot "execution") -Filter "stdout_*.txt"
  $Stderr = Get-LatestFile -Dir (Join-Path $ChildRoot "execution") -Filter "stderr_*.txt"
  $Diff = Get-LatestFile -Dir (Join-Path $ChildRoot "snapshots") -Filter "diff_from_previous.json"

  if([string]::IsNullOrWhiteSpace($Stdout)){
    [void]$Problems.Add("missing_stdout:" + $ChildSessionId)
  }

  if([string]::IsNullOrWhiteSpace($Stderr)){
    [void]$Problems.Add("missing_stderr:" + $ChildSessionId)
  }

  if([string]::IsNullOrWhiteSpace($Diff)){
    [void]$Problems.Add("missing_snapshot_diff:" + $ChildSessionId)
  }

  [void]$ChildRows.Add([pscustomobject][ordered]@{
    child_session_id = $ChildSessionId
    repo = [string]$R.repo
    capability_id = [string]$R.capability_id
    command = [string]$R.command
    status = [string]$R.status
    stdout = $Stdout
    stdout_sha256 = Get-Sha256OrEmpty $Stdout
    stderr = $Stderr
    stderr_sha256 = Get-Sha256OrEmpty $Stderr
    snapshot_diff = $Diff
    snapshot_diff_sha256 = Get-Sha256OrEmpty $Diff
  })
}

$Status = "ok"
if(@($Problems.ToArray()).Count -gt 0){
  $Status = "failed"
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$OutPath = Join-Path $OutRoot ("cross_repo_replay_aggregate_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_cross_repo_replay_aggregate.json"

$Aggregate = [ordered]@{
  schema = "pie.cross.repo.replay.aggregate.v1"
  session_id = $SessionId
  receipts = $ReceiptPath
  receipt_sha256 = Get-Sha256OrEmpty $ReceiptPath
  child_count = @($ChildRows.ToArray()).Count
  status = $Status
  problems = $Problems.ToArray()
  children = $ChildRows.ToArray()
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Aggregate | ConvertTo-Json -Depth 60
Write-Utf8NoBomLf -Path $OutPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

if($Status -ne "ok"){
  throw ("PIE_CROSS_REPO_REPLAY_AGGREGATE_FAIL: " + (@($Problems.ToArray()) -join ";"))
}

Write-Host ("PIE_CROSS_REPO_REPLAY_AGGREGATE_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("child_count: " + [string]@($ChildRows.ToArray()).Count)


