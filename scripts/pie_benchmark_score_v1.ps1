param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$BenchmarkRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if([string]::IsNullOrWhiteSpace($BenchmarkRoot)){
  $Root = Join-Path $RepoRoot "benchmarks\model_matrix"
  $Latest = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($null -eq $Latest){ throw "PIE_BENCHMARK_NO_RUNS_FOUND" }
  $BenchmarkRoot = $Latest.FullName
} else {
  $BenchmarkRoot = (Resolve-Path -LiteralPath $BenchmarkRoot).Path
}

$Rows = New-Object System.Collections.Generic.List[string]
[void]$Rows.Add("model,total,ok,fail,avg_elapsed_ms,score")

foreach($ModelDir in @(Get-ChildItem -LiteralPath $BenchmarkRoot -Directory)){
  $Files = @(Get-ChildItem -LiteralPath $ModelDir.FullName -File -Filter "*.txt" | Where-Object { $_.Name -ne "summary.txt" })
  $Total = @($Files).Count
  $Ok = 0
  $Fail = 0
  $Elapsed = New-Object System.Collections.Generic.List[int]

  foreach($File in $Files){
    $Text = Get-Content -LiteralPath $File.FullName -Raw
    if($Text -match "exit_code:\s*0"){ $Ok++ } else { $Fail++ }
    if($Text -match "elapsed_ms:\s*(\d+)"){ [void]$Elapsed.Add([int]$Matches[1]) }
  }

  $Avg = 0
  if(@($Elapsed).Count -gt 0){
    $Avg = [int]((@($Elapsed) | Measure-Object -Average).Average)
  }

  $Score = 0
  if($Total -gt 0){
    $Score = [math]::Round((($Ok / $Total) * 100),2)
  }

  [void]$Rows.Add($ModelDir.Name + "," + $Total + "," + $Ok + "," + $Fail + "," + $Avg + "," + $Score)
}

$Out = Join-Path $BenchmarkRoot "scorecard.csv"
[System.IO.File]::WriteAllText($Out,(($Rows.ToArray() -join "`n") + "`n"),(New-Object System.Text.UTF8Encoding($false)))

Write-Host ("PIE_BENCHMARK_SCORE_OK: " + $Out) -ForegroundColor Green
