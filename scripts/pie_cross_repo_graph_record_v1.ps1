param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SourceRepo,
  [Parameter(Mandatory=$true)][string]$TargetRepo,
  [Parameter(Mandatory=$true)][string]$Relation,
  [Parameter(Mandatory=$false)][string]$Purpose = "",
  [Parameter(Mandatory=$false)][string]$Evidence = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SourceRepo = (Resolve-Path -LiteralPath $SourceRepo).Path
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path

$GraphRoot = Join-Path $RepoRoot "memory\cross_repo_graph"
$GraphLog = Join-Path $GraphRoot "cross_repo_graph.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

if($Relation -notin @("depends_on","verifies_with","witnesses_to","policy_gated_by","identity_backed_by","related_to")){
  throw ("PIE_CROSS_REPO_BAD_RELATION: " + $Relation)
}

New-Item -ItemType Directory -Force -Path $GraphRoot | Out-Null

$Entry = [ordered]@{
  schema = "pie.cross.repo.edge.v1"
  source_repo = $SourceRepo
  source_name = Split-Path -Leaf $SourceRepo
  target_repo = $TargetRepo
  target_name = Split-Path -Leaf $TargetRepo
  relation = $Relation
  purpose = $Purpose
  evidence = $Evidence
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($GraphLog,(($Entry | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)

Write-Host ("PIE_CROSS_REPO_GRAPH_RECORD_OK: " + $Relation) -ForegroundColor Green
Write-Host ("source: " + $SourceRepo)
Write-Host ("target: " + $TargetRepo)
