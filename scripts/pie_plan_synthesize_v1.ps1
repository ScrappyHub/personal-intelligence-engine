param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SessionId,
  [Parameter(Mandatory=$true)][string]$Goal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunRoot = Join-Path $RepoRoot ("runs\" + $SessionId)
$OutRoot = Join-Path $RunRoot "synthesized_plans"
$Enc = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $Dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
  $Clean = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $Clean.EndsWith("`n")){ $Clean += "`n" }
  [System.IO.File]::WriteAllText($Path,$Clean,$Enc)
}

if(-not (Test-Path -LiteralPath $RunRoot -PathType Container)){
  throw ("PIE_SYNTH_SESSION_NOT_FOUND: " + $SessionId)
}

$QueryJson = @(
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File (Join-Path $RepoRoot "scripts\pie_cognition_graph_query_v1.ps1") `
    -RepoRoot $RepoRoot `
    -Outcome "success"
) -join "`n"

if($LASTEXITCODE -ne 0){ throw "PIE_SYNTH_GRAPH_QUERY_FAIL" }

$Query = $QueryJson | ConvertFrom-Json

$SelectedKey = ""
$SelectedScore = 0
$Reason = "NO_SUCCESSFUL_SEQUENCE_DEFAULT_USED"
$Sequence = @("repo.status","repo.diff")

if($Query.scores){
  $Pairs = New-Object System.Collections.Generic.List[object]

  foreach($Prop in $Query.scores.PSObject.Properties){
    [void]$Pairs.Add([pscustomobject]@{
      key = [string]$Prop.Name
      score = [int]$Prop.Value
    })
  }

  $Best = @($Pairs.ToArray()) |
    Sort-Object @{ Expression = "score"; Descending = $true }, @{ Expression = "key"; Descending = $false } |
    Select-Object -First 1

  if($null -ne $Best -and [int]$Best.score -gt 0){
    $SelectedKey = [string]$Best.key
    $SelectedScore = [int]$Best.score
    $Sequence = @($SelectedKey.Split("->") | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $Reason = "COGNITION_GRAPH_BEST_SUCCESS_SEQUENCE"
  }
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$PlanPath = Join-Path $OutRoot ("synth_plan_" + $Stamp + ".json")
$LatestPath = Join-Path $OutRoot "latest_synth_plan.json"

$Plan = [ordered]@{
  schema = "pie.synthesized.plan.v1"
  session_id = $SessionId
  goal = $Goal
  selected_sequence_key = $SelectedKey
  selected_score = $SelectedScore
  sequence = $Sequence
  reason_code = $Reason
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$Json = $Plan | ConvertTo-Json -Depth 20
Write-Utf8NoBomLf -Path $PlanPath -Text $Json
Write-Utf8NoBomLf -Path $LatestPath -Text $Json

Write-Host ("PIE_SYNTH_PLAN_OK: " + $PlanPath) -ForegroundColor Green
Write-Host ("sequence: " + ($Sequence -join " -> "))
