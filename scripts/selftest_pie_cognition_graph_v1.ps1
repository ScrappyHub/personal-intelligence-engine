param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SessionId = "pie_cognition_graph_selftest"
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$GraphLog = Join-Path $RepoRoot "memory\cognition_graph\cognition_graph.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(Test-Path -LiteralPath $RunRoot -PathType Container){
  Remove-Item -LiteralPath $RunRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "project_repo.txt") -Text $RepoRoot

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_cognition_graph_record_v1.ps1") `
  -RepoRoot $RepoRoot `
  -Goal "repo health" `
  -SequenceCsv "repo.status,repo.diff" `
  -Outcome "success" `
  -Evidence "selftest seed" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_COG_GRAPH_RECORD_CHILD_FAIL" }

if(-not (Test-Path -LiteralPath $GraphLog -PathType Leaf)){ throw "PIE_COG_GRAPH_LOG_MISSING" }

$QueryJson = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_cognition_graph_query_v1.ps1") `
    -RepoRoot $RepoRoot `
    -Outcome "success"
) -join "`n"

if($LASTEXITCODE -ne 0){ throw "PIE_COG_GRAPH_QUERY_CHILD_FAIL" }

$Query = $QueryJson | ConvertFrom-Json
if($Query.count -lt 1){ throw "PIE_COG_GRAPH_QUERY_EMPTY" }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File (Join-Path $RepoRoot "scripts\pie_plan_synthesize_v1.ps1") `
  -RepoRoot $RepoRoot `
  -SessionId $SessionId `
  -Goal "synthesize repo health plan" | Out-Host

if($LASTEXITCODE -ne 0){ throw "PIE_SYNTH_CHILD_FAIL" }

$Latest = Join-Path $RunRoot "synthesized_plans\latest_synth_plan.json"
if(-not (Test-Path -LiteralPath $Latest -PathType Leaf)){ throw "PIE_SYNTH_LATEST_MISSING" }

$Plan = Get-Content -LiteralPath $Latest -Raw | ConvertFrom-Json
if(-not (@($Plan.sequence) -contains "repo.status")){ throw "PIE_SYNTH_MISSING_STATUS" }
if(-not (@($Plan.sequence) -contains "repo.diff")){ throw "PIE_SYNTH_MISSING_DIFF" }

Write-Host "PIE_COGNITION_GRAPH_SELFTEST_OK" -ForegroundColor Green
