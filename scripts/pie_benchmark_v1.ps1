param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Trials = Join-Path $RepoRoot "benchmarks\workbench_trials_v1\trials.jsonl"
$RespDir = Join-Path $RepoRoot "benchmarks\workbench_trials_v1\responses"
$total=0; $pass=0
Get-Content -LiteralPath $Trials | ForEach-Object {
  if($_.Trim() -eq ""){ return }
  $t = $_ | ConvertFrom-Json
  $total++
  $rp = Join-Path $RespDir ($t.trial_id + ".txt")
  if(-not (Test-Path -LiteralPath $rp -PathType Leaf)){ return }
  $r = Get-Content -LiteralPath $rp -Raw
  $ok=$true
  foreach($m in @($t.must_include)){ if($r.IndexOf([string]$m,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ $ok=$false } }
  if($ok){ $pass++ }
}
if($total -lt 1 -or $pass -ne $total){ throw ("PIE_BENCHMARK_FAIL " + $pass + "/" + $total) }
Write-Host "PIE_BENCHMARK_V1_GREEN" -ForegroundColor Green
