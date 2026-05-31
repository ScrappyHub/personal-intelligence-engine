param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Goal,
  [Parameter(Mandatory=$true)][string]$SequenceCsv,
  [Parameter(Mandatory=$true)][string]$Outcome,
  [Parameter(Mandatory=$false)][string]$Evidence = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$GraphRoot = Join-Path $RepoRoot "memory\cognition_graph"
$GraphLog = Join-Path $GraphRoot "cognition_graph.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

if($Outcome -notin @("success","failure","partial")){
  throw ("PIE_COG_GRAPH_BAD_OUTCOME: " + $Outcome)
}

$Seq = @($SequenceCsv.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if(@($Seq).Count -lt 1){ throw "PIE_COG_GRAPH_SEQUENCE_EMPTY" }

New-Item -ItemType Directory -Force -Path $GraphRoot | Out-Null

$Entry = [ordered]@{
  schema = "pie.cognition.graph.entry.v1"
  goal = $Goal
  sequence = $Seq
  sequence_key = ($Seq -join " -> ")
  outcome = $Outcome
  evidence = $Evidence
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($GraphLog,(($Entry | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)

Write-Host ("PIE_COG_GRAPH_RECORD_OK: " + $GraphLog) -ForegroundColor Green
