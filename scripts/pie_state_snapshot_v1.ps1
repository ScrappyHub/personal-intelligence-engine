param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$false)][string]$TargetPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$SnapshotRoot = Join-Path $RunRoot "snapshots"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

function Test-IgnoredPath {
  param([string]$Rel)
  $R = $Rel.Replace("/","\").ToLowerInvariant()
  if($R -match '(^|\\)\.git(\\|$)'){ return $true }
  if($R -match '(^|\\)runs(\\|$)'){ return $true }
  if($R -match '(^|\\)proofs\\freeze(\\|$)'){ return $true }
  if($R -match '(^|\\)node_modules(\\|$)'){ return $true }
  if($R -match '(^|\\)dist(\\|$)'){ return $true }
  if($R -match '(^|\\)build(\\|$)'){ return $true }
  if($R -match '(^|\\)bin(\\|$)'){ return $true }
  if($R -match '(^|\\)obj(\\|$)'){ return $true }
  return $false
}

function Get-Sha256 {
  param([string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
}

if([string]::IsNullOrWhiteSpace($TargetPath)){
  $ProjectRepoFile = Join-Path $RunRoot "project_repo.txt"
  if(Test-Path -LiteralPath $ProjectRepoFile -PathType Leaf){
    $TargetPath = (Get-Content -LiteralPath $ProjectRepoFile -Raw).Trim()
  }
}

if([string]::IsNullOrWhiteSpace($TargetPath)){
  $TargetPath = $RepoRoot
}

if(-not (Test-Path -LiteralPath $TargetPath -PathType Container)){
  throw ("PIE_SNAPSHOT_TARGET_NOT_FOUND: " + $TargetPath)
}

$TargetPath = (Resolve-Path -LiteralPath $TargetPath).Path

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$SnapshotId = "snapshot_" + $Stamp
$SnapshotDir = Join-Path $SnapshotRoot $SnapshotId
$InventoryPath = Join-Path $SnapshotDir "inventory.ndjson"
$SummaryPath = Join-Path $SnapshotDir "snapshot.json"

New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null

$Files = @(Get-ChildItem -LiteralPath $TargetPath -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
$Count = 0
$Bytes = [int64]0

foreach($File in $Files){
  $Full = [string]$File.FullName
  if(-not $Full.StartsWith($TargetPath,[System.StringComparison]::OrdinalIgnoreCase)){ continue }

  $Rel = $Full.Substring($TargetPath.Length).TrimStart("\")
  if(Test-IgnoredPath -Rel $Rel){ continue }

  $Hash = Get-Sha256 -Path $Full
  $Bytes += [int64]$File.Length
  $Count++

  $Row = [ordered]@{
    schema = "pie.state.snapshot.file.v1"
    rel = $Rel
    length = [int64]$File.Length
    sha256 = $Hash
  }

  [System.IO.File]::AppendAllText($InventoryPath,(($Row | ConvertTo-Json -Depth 8 -Compress) + "`n"),$Enc)
}

$Summary = [ordered]@{
  schema = "pie.state.snapshot.v1"
  snapshot_id = $SnapshotId
  session_id = $SessionId
  target_path = $TargetPath
  inventory = $InventoryPath
  file_count = $Count
  total_bytes = $Bytes
  created_utc = [DateTime]::UtcNow.ToString("o")
}

Write-Utf8NoBomLf -Path $SummaryPath -Text ($Summary | ConvertTo-Json -Depth 12)

Write-Host ("PIE_STATE_SNAPSHOT_OK: " + $SummaryPath) -ForegroundColor Green
