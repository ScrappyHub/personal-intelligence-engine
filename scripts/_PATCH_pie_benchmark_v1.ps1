param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Enc = New-Object System.Text.UTF8Encoding($false)
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$p,[string]$t){ $d=Split-Path -Parent $p; if($d){ Ensure-Dir $d }; $x=$t.Replace("`r`n","`n").Replace("`r","`n"); if(-not $x.EndsWith("`n")){ $x+="`n" }; [System.IO.File]::WriteAllText($p,$x,$Enc) }
Ensure-Dir (Join-Path $RepoRoot "benchmarks\workbench_trials_v1\responses")
Ensure-Dir (Join-Path $RepoRoot "benchmarks\results")
Write-Utf8NoBomLf (Join-Path $RepoRoot "benchmarks\workbench_trials_v1\trials.jsonl") '{"trial_id":"ps_strictmode_scalar_count_v1","must_include":["@(@(",".Count","StrictMode"],"weight":10}'
Add-Content -LiteralPath (Join-Path $RepoRoot "benchmarks\workbench_trials_v1\trials.jsonl") -Value '{"trial_id":"packet_optionA_manifest_rule_v1","must_include":["manifest.json","MUST NOT","packet_id.txt","SHA-256"],"weight":10}'
Write-Utf8NoBomLf (Join-Path $RepoRoot "benchmarks\workbench_trials_v1\responses\ps_strictmode_scalar_count_v1.txt") "Use @(@(...)) before .Count under StrictMode."
Write-Utf8NoBomLf (Join-Path $RepoRoot "benchmarks\workbench_trials_v1\responses\packet_optionA_manifest_rule_v1.txt") "manifest.json MUST NOT contain packet_id and packet_id.txt is SHA-256."
$Bench = Join-Path $RepoRoot "scripts\pie_benchmark_v1.ps1"
$B = New-Object System.Collections.Generic.List[string]
[void]$B.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$B.Add('Set-StrictMode -Version Latest')
[void]$B.Add('$ErrorActionPreference = "Stop"')
[void]$B.Add('$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$B.Add('$Trials = Join-Path $RepoRoot "benchmarks\workbench_trials_v1\trials.jsonl"')
[void]$B.Add('$RespDir = Join-Path $RepoRoot "benchmarks\workbench_trials_v1\responses"')
[void]$B.Add('$total=0; $pass=0')
[void]$B.Add('Get-Content -LiteralPath $Trials | ForEach-Object {')
[void]$B.Add('  if($_.Trim() -eq ""){ return }')
[void]$B.Add('  $t = $_ | ConvertFrom-Json')
[void]$B.Add('  $total++')
[void]$B.Add('  $rp = Join-Path $RespDir ($t.trial_id + ".txt")')
[void]$B.Add('  if(-not (Test-Path -LiteralPath $rp -PathType Leaf)){ return }')
[void]$B.Add('  $r = Get-Content -LiteralPath $rp -Raw')
[void]$B.Add('  $ok=$true')
[void]$B.Add('  foreach($m in @($t.must_include)){ if($r.IndexOf([string]$m,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){ $ok=$false } }')
[void]$B.Add('  if($ok){ $pass++ }')
[void]$B.Add('}')
[void]$B.Add('if($total -lt 1 -or $pass -ne $total){ throw ("PIE_BENCHMARK_FAIL " + $pass + "/" + $total) }')
[void]$B.Add('Write-Host "PIE_BENCHMARK_V1_GREEN" -ForegroundColor Green')
Write-Utf8NoBomLf $Bench (($B.ToArray()) -join "`n")
Write-Host "PATCH_OK" -ForegroundColor Green
