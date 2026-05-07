param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$Model = "",
  [switch]$LastResults,
  [switch]$Scorecard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$BenchRoot = Join-Path $RepoRoot "benchmarks\model_matrix"

if(-not (Test-Path -LiteralPath $BenchRoot -PathType Container)){
  throw "PIE_SHOW_NO_BENCHMARK_ROOT"
}

$Latest = Get-ChildItem -LiteralPath $BenchRoot -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if($null -eq $Latest){
  throw "PIE_SHOW_NO_BENCHMARK_RUNS"
}

$ScorePath = Join-Path $Latest.FullName "scorecard.csv"

Write-Host ""
Write-Host ("PIE Latest Benchmark: " + $Latest.Name) -ForegroundColor Cyan
Write-Host ("Path: " + $Latest.FullName)
Write-Host ""

if($Scorecard -or $LastResults -or [string]::IsNullOrWhiteSpace($Model)){
  if(Test-Path -LiteralPath $ScorePath -PathType Leaf){
    Import-Csv -LiteralPath $ScorePath | Format-Table -AutoSize
  } else {
    Write-Host "No scorecard.csv found. Run: pie score" -ForegroundColor Yellow
  }
}

if(-not [string]::IsNullOrWhiteSpace($Model)){
  $SafeModel = ($Model -replace '[^a-zA-Z0-9._-]','_')
  $ModelDir = Join-Path $Latest.FullName $SafeModel

  if(-not (Test-Path -LiteralPath $ModelDir -PathType Container)){
    throw ("PIE_SHOW_MODEL_NOT_FOUND: " + $Model)
  }

  Write-Host ""
  Write-Host ("Model Results: " + $Model) -ForegroundColor Cyan

  Get-ChildItem -LiteralPath $ModelDir -File -Filter "*.txt" |
    Where-Object { $_.Name -notlike "*.err.txt" } |
    Sort-Object Name |
    ForEach-Object {
      Write-Host ""
      Write-Host ("--- " + $_.Name + " ---") -ForegroundColor DarkCyan
      Get-Content -LiteralPath $_.FullName -TotalCount 80
    }
}