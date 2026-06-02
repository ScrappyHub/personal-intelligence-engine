param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetRepo,
  [Parameter(Mandatory=$true)][string]$TemplateId,
  [Parameter(Mandatory=$true)][string]$SequenceCsv,
  [Parameter(Mandatory=$false)][string]$Purpose = "",
  [Parameter(Mandatory=$false)][string]$Evidence = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path

$TemplateRoot = Join-Path $RepoRoot "memory\repo_templates"
$TemplateLog = Join-Path $TemplateRoot "repo_templates.ndjson"
$Enc = New-Object System.Text.UTF8Encoding($false)

$Seq = @(
  $SequenceCsv.Split(",") |
  ForEach-Object { $_.Trim() } |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

if(@($Seq).Count -lt 1){
  throw "PIE_REPO_TEMPLATE_SEQUENCE_EMPTY"
}

if([string]::IsNullOrWhiteSpace($TemplateId)){
  throw "PIE_REPO_TEMPLATE_ID_REQUIRED"
}

New-Item -ItemType Directory -Force -Path $TemplateRoot | Out-Null

$RepoName = Split-Path -Leaf $TargetRepo

$Entry = [ordered]@{
  schema = "pie.repo.template.entry.v1"
  template_id = $TemplateId
  repo = $TargetRepo
  repo_name = $RepoName
  purpose = $Purpose
  sequence = $Seq
  sequence_key = ($Seq -join " -> ")
  evidence = $Evidence
  created_utc = [DateTime]::UtcNow.ToString("o")
}

[System.IO.File]::AppendAllText($TemplateLog,(($Entry | ConvertTo-Json -Depth 20 -Compress) + "`n"),$Enc)

Write-Host ("PIE_REPO_TEMPLATE_RECORD_OK: " + $TemplateId) -ForegroundColor Green
